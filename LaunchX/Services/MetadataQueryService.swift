import Cocoa
import Combine
import Foundation

/// A high-performance service that builds and maintains an in-memory index
/// of files using the high-level NSMetadataQuery API.
///
/// Workflow:
/// 1. Uses NSMetadataQuery to fetch metadata for configured scopes efficiently.
/// 2. Captures results snapshot on the main thread (fast).
/// 3. Offloads metadata extraction and heavy processing (Pinyin) to concurrent background threads.
/// 4. Splits index into Apps and Files for prioritized searching.
/// 5. Provides async search with batch processing to allow rapid cancellation.
class MetadataQueryService: ObservableObject {
    static let shared = MetadataQueryService()

    @Published var isIndexing: Bool = false
    @Published var indexedItemCount: Int = 0

    // Split index for optimization
    // IndexedItem is a class, so array copies are cheap (copying references)
    private var appsIndex: [IndexedItem] = []
    private var filesIndex: [IndexedItem] = []

    // Processing queue for search requests
    private let searchQueue = DispatchQueue(
        label: "com.launchx.metadata.search", qos: .userInteractive)

    // Global concurrent queue for heavy indexing
    private let indexingQueue = DispatchQueue.global(qos: .userInitiated)

    private var query: NSMetadataQuery?
    private var searchConfig: SearchConfig = SearchConfig()

    // Cancellation token for search requests
    private var currentSearchWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Public API

    func startIndexing(with config: SearchConfig) {
        DispatchQueue.main.async {
            self.stopIndexing()
            self.searchConfig = config
            self.isIndexing = true

            let query = NSMetadataQuery()
            self.query = query

            query.searchScopes = config.searchScopes

            // Predicate: public.item, excluding prefpanes
            let predicate = NSPredicate(
                format: "%K == 'public.item' AND %K != 'com.apple.systempreference.prefpane'",
                NSMetadataItemContentTypeTreeKey,
                NSMetadataItemContentTypeKey
            )
            query.predicate = predicate

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidFinishGathering(_:)),
                name: .NSMetadataQueryDidFinishGathering,
                object: query
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidUpdate(_:)),
                name: .NSMetadataQueryDidUpdate,
                object: query
            )

            print(
                "MetadataQueryService: Starting NSMetadataQuery with scopes: \(config.searchScopes)"
            )
            if !query.start() {
                print("MetadataQueryService: Failed to start NSMetadataQuery")
                self.isIndexing = false
            }
        }
    }

    func stopIndexing() {
        if let query = query {
            query.stop()
            NotificationCenter.default.removeObserver(
                self, name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.removeObserver(
                self, name: .NSMetadataQueryDidUpdate, object: query)
            self.query = nil
            self.isIndexing = false
        }
    }

    // MARK: - Search Logic

    /// Synchronous search for immediate results - called on every keystroke
    /// This must be EXTREMELY fast (< 1ms) to not block typing
    /// HapiGo-style: pure in-memory query, no I/O, no thread switching
    func searchSync(text: String) -> [IndexedItem] {
        guard !text.isEmpty else { return [] }

        let lowerQuery = text.lowercased()

        // 1. Search Apps first (usually small, ~100-500 items)
        var matchedApps: [IndexedItem] = []
        matchedApps.reserveCapacity(10)

        for app in appsIndex {
            // Ultra-fast path: prefix match on lowercase name (pre-computed)
            if app.lowerName.hasPrefix(lowerQuery) {
                matchedApps.append(app)
                if matchedApps.count >= 10 { break }
                continue
            }
            // Fast path: contains match
            if app.lowerName.contains(lowerQuery) {
                matchedApps.append(app)
                if matchedApps.count >= 10 { break }
            }
            // NOTE: Pinyin matching disabled in sync search for speed
        }

        // Sort apps: prefix matches first, then by name length
        matchedApps.sort { lhs, rhs in
            let lPrefix = lhs.lowerName.hasPrefix(lowerQuery)
            let rPrefix = rhs.lowerName.hasPrefix(lowerQuery)
            if lPrefix && !rPrefix { return true }
            if !lPrefix && rPrefix { return false }
            return lhs.name.count < rhs.name.count
        }

        // 2. Search Files (limit iterations for speed)
        var matchedFiles: [IndexedItem] = []
        matchedFiles.reserveCapacity(20)

        let maxFileIterations = min(filesIndex.count, 5000)  // Cap iterations
        for i in 0..<maxFileIterations {
            let file = filesIndex[i]

            if file.lowerName.hasPrefix(lowerQuery) {
                matchedFiles.append(file)
                if matchedFiles.count >= 20 { break }
                continue
            }
            if file.lowerName.contains(lowerQuery) {
                matchedFiles.append(file)
                if matchedFiles.count >= 20 { break }
            }
        }

        // Sort files by relevance
        matchedFiles.sort { lhs, rhs in
            let lPrefix = lhs.lowerName.hasPrefix(lowerQuery)
            let rPrefix = rhs.lowerName.hasPrefix(lowerQuery)
            if lPrefix && !rPrefix { return true }
            if !lPrefix && rPrefix { return false }
            return lhs.lastUsed > rhs.lastUsed
        }

        // Combine: Apps first (max 10), then Files (max 20)
        let topApps = Array(matchedApps.prefix(10))
        let topFiles = Array(matchedFiles.prefix(20))

        return topApps + topFiles
    }

    /// Async search with batch processing for responsiveness.
    /// - Parameters:
    ///   - text: The search query.
    ///   - completion: Callback with results (Apps first, then Files).
    func search(text: String, completion: @escaping ([IndexedItem]) -> Void) {
        // Cancel previous pending search
        currentSearchWorkItem?.cancel()

        guard !text.isEmpty else {
            completion([])
            return
        }

        // Snapshot indices (Cheap pointer copy since IndexedItem is a class)
        let apps = self.appsIndex
        let files = self.filesIndex

        // Pre-compute query specifics once
        let lowerQuery = text.lowercased()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Helper to check cancellation
            func isCancelled() -> Bool {
                return self.currentSearchWorkItem?.isCancelled ?? true
            }

            if isCancelled() { return }

            // 1. Apps Search (Batch processing)
            var matchedApps: [IndexedItem] = []
            let appChunkSize = 200

            for i in stride(from: 0, to: apps.count, by: appChunkSize) {
                if isCancelled() { return }

                let end = min(i + appChunkSize, apps.count)
                let chunk = apps[i..<end]

                for app in chunk {
                    // Extremely fast path: contains check on pre-computed lowercase name
                    if app.lowerName.contains(lowerQuery) {
                        matchedApps.append(app)
                        continue
                    }
                    // Slow path: Pinyin (only check if fast path fails)
                    if app.searchableName.matches(text) {
                        matchedApps.append(app)
                    }
                }
            }

            // Sort Apps
            let sortedApps = matchedApps.sorted { lhs, rhs in
                // Exact match priority
                if lhs.lowerName == lowerQuery { return true }
                if rhs.lowerName == lowerQuery { return false }

                // Prefix priority
                let lPrefix = lhs.lowerName.hasPrefix(lowerQuery)
                let rPrefix = rhs.lowerName.hasPrefix(lowerQuery)
                if lPrefix && !rPrefix { return true }
                if !lPrefix && rPrefix { return false }

                // Usage/Date priority
                return lhs.lastUsed > rhs.lastUsed
            } 

            let topApps = Array(sortedApps.prefix(10))

            if isCancelled() { return }

            // 2. Files Search (Batch processing)
            var matchedFiles: [IndexedItem] = []
            let fileChunkSize = 1000  // Process files in larger chunks

            for i in stride(from: 0, to: files.count, by: fileChunkSize) {
                if isCancelled() { return }

                let end = min(i + fileChunkSize, files.count)
                let chunk = files[i..<end]

                for file in chunk {
                    if file.lowerName.contains(lowerQuery) {
                        matchedFiles.append(file)
                        continue
                    }
                    if file.searchableName.matches(text) {
                        matchedFiles.append(file)
                    }
                }
            }

            let sortedFiles = matchedFiles.sorted { lhs, rhs in
                return lhs.lastUsed > rhs.lastUsed
            }

            let topFiles = Array(sortedFiles.prefix(20))

            let combined = topApps + topFiles

            DispatchQueue.main.async {
                // Ensure we are still the relevant search
                if !isCancelled() {
                    completion(combined)
                }
            }
        }

        self.currentSearchWorkItem = workItem
        searchQueue.async(execute: workItem)
    }

    // MARK: - Handlers

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        print("MetadataQueryService: NSMetadataQuery finished gathering")
        processQueryResults(isInitial: true)
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults(isInitial: false)
    }

    private func processQueryResults(isInitial: Bool) {
        guard let query = query else { return }

        // Pause live updates to ensure stability during iteration
        query.disableUpdates()

        // Capture snapshot on Main Thread (fast)
        let results = query.results as? [NSMetadataItem] ?? []

        // Resume updates immediately
        query.enableUpdates()

        if results.isEmpty {
            if isInitial { isIndexing = false }
            return
        }

        // Offload ALL processing to background
        indexingQueue.async { [weak self] in
            guard let self = self else { return }

            let count = results.count
            // Use UnsafeMutablePointer for lock-free parallel writing of object references
            let tempBuffer = UnsafeMutablePointer<IndexedItem?>.allocate(capacity: count)
            tempBuffer.initialize(repeating: nil, count: count)

            defer {
                tempBuffer.deinitialize(count: count)
                tempBuffer.deallocate()
            }

            // Capture config for thread safety
            let excludedPaths = self.searchConfig.excludedPaths
            let excludedNames = self.searchConfig.excludedNames
            let excludedNamesSet = Set(excludedNames)

            // Parallel Loop
            DispatchQueue.concurrentPerform(iterations: count) { i in
                let item = results[i]

                guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                    return
                }

                let pathComponents = path.components(separatedBy: "/")

                // Filtering
                if !excludedNamesSet.isDisjoint(with: pathComponents) { return }

                if !excludedPaths.isEmpty {
                    if excludedPaths.contains(where: { path.hasPrefix($0) }) { return }
                }

                // Prioritize Display Name
                let name =
                    item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                    ?? item.value(forAttribute: NSMetadataItemFSNameKey) as? String
                    ?? (path as NSString).lastPathComponent

                let date =
                    item.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date
                    ?? Date()

                let contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String

                // Object Creation (Heavy Pinyin Calculation happens here inside init)
                let isDirectory =
                    (contentType == "public.folder" || contentType == "com.apple.mount-point")
                let isApp = (contentType == "com.apple.application-bundle")

                let indexedItem = IndexedItem(
                    name: name,
                    path: path,
                    lastUsed: date,
                    isDirectory: isDirectory,
                    isApp: isApp,
                    searchableName: CachedSearchableString(name)
                )

                tempBuffer[i] = indexedItem
            }

            // Collect results
            var newApps: [IndexedItem] = []
            var newFiles: [IndexedItem] = []
            newApps.reserveCapacity(500)
            newFiles.reserveCapacity(count)

            for i in 0..<count {
                if let item = tempBuffer[i] {
                    if item.isApp {
                        newApps.append(item)
                    } else {
                        newFiles.append(item)
                    }
                }
            }

            // Initial sort for Apps
            newApps.sort { $0.name.count < $1.name.count }

            // Update State on Main Thread
            DispatchQueue.main.async {
                self.appsIndex = newApps
                self.filesIndex = newFiles
                self.indexedItemCount = newApps.count + newFiles.count
                self.isIndexing = false

                if isInitial {
                    print(
                        "MetadataQueryService: Indexing complete. Apps: \(newApps.count), Files: \(newFiles.count)"
                    )

                    // Pre-load icons for apps in background (apps are most frequently accessed)
                    DispatchQueue.global(qos: .utility).async {
                        for app in newApps {
                            app.preloadIcon()
                        }
                        print("MetadataQueryService: App icons preloaded")
                    }
                }
            }
        }
    }
}

// MARK: - Models

/// Changed from struct to final class to avoid Copy-On-Write overhead during search filtering
final class IndexedItem: Identifiable {
    let id = UUID()
    let name: String
    let lowerName: String
    let path: String
    let lastUsed: Date
    let isDirectory: Bool
    let isApp: Bool
    let searchableName: CachedSearchableString

    // Pre-cached icon - loaded during indexing, not during display
    private var _icon: NSImage?
    private var iconLoaded = false
    private let iconLock = NSLock()

    var icon: NSImage {
        iconLock.lock()
        defer { iconLock.unlock() }

        if !iconLoaded {
            _icon = NSWorkspace.shared.icon(forFile: path)
            _icon?.size = NSSize(width: 32, height: 32)
            iconLoaded = true
        }
        return _icon ?? NSImage()
    }

    // Pre-load icon in background (call this during indexing)
    func preloadIcon() {
        iconLock.lock()
        if iconLoaded {
            iconLock.unlock()
            return
        }
        iconLock.unlock()

        _icon = NSWorkspace.shared.icon(forFile: path)
        _icon?.size = NSSize(width: 32, height: 32)

        iconLock.lock()
        iconLoaded = true
        iconLock.unlock()
    }

    init(
        name: String, path: String, lastUsed: Date, isDirectory: Bool, isApp: Bool,
        searchableName: CachedSearchableString
    ) {
        self.name = name
        self.lowerName = name.lowercased()  // Pre-compute for fast search
        self.path = path
        self.lastUsed = lastUsed
        self.isDirectory = isDirectory
        self.isApp = isApp
        self.searchableName = searchableName
    }

    func toSearchResult() -> SearchResult {
        return SearchResult(
            id: id,
            name: name,
            path: path,
            icon: icon,  // Use pre-cached icon
            isDirectory: isDirectory
        )
    }
}
