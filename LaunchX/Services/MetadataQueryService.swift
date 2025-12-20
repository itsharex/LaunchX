import Cocoa
import Combine
import CoreServices

/// A high-performance service that builds and maintains an in-memory index
/// of files using the system Spotlight (MDQuery) API.
///
/// Workflow:
/// 1. Uses MDQuery to fetch metadata for configured scopes efficiently.
/// 2. Filters out excluded paths (e.g., node_modules) during ingestion.
/// 3. Caches results in memory wrapped in `CachedSearchableString` for fast Pinyin matching.
/// 4. Listens for live updates from the system index.
class MetadataQueryService: ObservableObject {
    static let shared = MetadataQueryService()

    @Published var isIndexing: Bool = false
    @Published var indexedItemCount: Int = 0

    // The main in-memory index
    private(set) var indexedItems: [IndexedItem] = []

    private var query: MDQuery?
    private var searchConfig: SearchConfig = SearchConfig()

    // Serial queue for processing index updates to avoid race conditions
    private let indexQueue = DispatchQueue(label: "com.launchx.metadata.index", qos: .utility)

    private init() {}

    // MARK: - Public API

    /// Starts or restarts the indexing process based on the provided configuration.
    func startIndexing(with config: SearchConfig) {
        DispatchQueue.main.async {
            self.searchConfig = config
            self.isIndexing = true
        }

        // Perform setup on background queue to avoid blocking/crashing main thread
        indexQueue.async { [weak self] in
            guard let self = self else { return }

            // Stop existing query if any
            if let query = self.query {
                MDQueryStop(query)
                self.query = nil
            }

            // Construct the MDQuery string
            // We want all items in the scope, usually Applications and user documents.
            let queryString = """
                kMDItemContentTypeTree == "public.item" &&
                kMDItemContentType != "com.apple.systempreference.prefpane"
                """ as CFString

            // Use kCFAllocatorDefault for create
            guard let query = MDQueryCreate(kCFAllocatorDefault, queryString, nil, nil) else {
                print("Failed to create MDQuery")
                DispatchQueue.main.async {
                    self.isIndexing = false
                }
                return
            }

            // Set Search Scopes (Directories)
            // MDQuerySetSearchScope takes an array of CFURLs
            let scopeURLs = config.searchScopes.map { URL(fileURLWithPath: $0) as CFURL }
            MDQuerySetSearchScope(query, scopeURLs as CFArray, 0)

            // Set Update Handler (Batching is handled by MDQuery but we process on main or background?)
            // MDQuerySetDispatchQueue allows us to receive callbacks on a specific queue.
            MDQuerySetDispatchQueue(query, self.indexQueue)

            // Notification observers for query phases.
            // Using string literals for stability across Swift versions where constants might be hidden or renamed.
            let finishName = Notification.Name("kMDQueryDidFinishGatheringNotification")
            let updateName = Notification.Name("kMDQueryDidUpdateNotification")

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidFinishGathering(_:)),
                name: finishName,
                object: query
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidUpdate(_:)),
                name: updateName,
                object: query
            )

            self.query = query

            // Start the query
            // Fix: Use literal 1 for kMDQueryWantsUpdates to avoid type casting issues with MDQueryOptionFlags struct
            if !MDQueryExecute(query, 1) {
                print("Failed to execute MDQuery")
                DispatchQueue.main.async {
                    self.isIndexing = false
                }
            }
        }
    }

    /// Fast in-memory search using Pinyin matcher
    func search(text: String, limit: Int = 50) -> [IndexedItem] {
        guard !text.isEmpty else { return [] }

        var results: [IndexedItem] = []

        // Thread-safe read
        indexQueue.sync {
            // Filter
            let matches = indexedItems.filter { item in
                item.searchableName.matches(text)
            }

            // Sort (Score matching could be added here, e.g. prefix match vs substring)
            // For now, simple length based or original order (Spotlight returns loosely sorted)
            let sorted = matches.sorted { lhs, rhs in
                // Prefer shorter names (exact matches)
                if lhs.name.count != rhs.name.count {
                    return lhs.name.count < rhs.name.count
                }
                // Prefer newer files
                return lhs.lastUsed > rhs.lastUsed
            }

            results = Array(sorted.prefix(limit))
        }

        return results
    }

    // MARK: - Query Handlers

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults(isInitial: true)
        DispatchQueue.main.async {
            self.isIndexing = false
        }
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults(isInitial: false)
    }

    private func processQueryResults(isInitial: Bool) {
        guard let query = self.query else { return }

        let count = MDQueryGetResultCount(query)
        var newItems: [IndexedItem] = []
        newItems.reserveCapacity(count)

        // Prepare exclusion checks
        let excludedPaths = searchConfig.excludedPaths
        let excludedNames = searchConfig.excludedNames

        for i in 0..<count {
            guard let rawPtr = MDQueryGetResultAtIndex(query, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(rawPtr).takeUnretainedValue()

            // Get Path
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }

            // --- High Performance Filtering ---

            // 1. Path Exclusion (e.g. inside .git or node_modules)
            let pathComponents = path.components(separatedBy: "/")

            // Optimization: Quick check if any excluded name exists in path
            let hasExcludedName = !Set(pathComponents).isDisjoint(with: excludedNames)
            if hasExcludedName { continue }

            // 2. Exact Path Exclusion
            if excludedPaths.contains(where: { path.hasPrefix($0) }) { continue }

            // --- Extraction ---

            let name =
                MDItemCopyAttribute(item, kMDItemDisplayName) as? String
                ?? (path as NSString).lastPathComponent
            let date = MDItemCopyAttribute(item, kMDItemContentModificationDate) as? Date ?? Date()

            // Check if directory
            let contentType = MDItemCopyAttribute(item, kMDItemContentType) as? String
            let isDirectory =
                (contentType == "public.folder" || contentType == "com.apple.mount-point")

            let cachedItem = IndexedItem(
                id: UUID(),
                name: name,
                path: path,
                lastUsed: date,
                isDirectory: isDirectory,
                searchableName: CachedSearchableString(name)
            )

            newItems.append(cachedItem)
        }

        // Update State
        DispatchQueue.main.async { [weak self] in
            self?.indexedItems = newItems
            self?.indexedItemCount = newItems.count
            if isInitial {
                print(
                    "MetadataQueryService: Initial index complete. Total items: \(newItems.count)")
            } else {
                print("MetadataQueryService: Index updated. Total items: \(newItems.count)")
            }
        }
    }
}

// MARK: - Models

struct IndexedItem: Identifiable {
    let id: UUID
    let name: String
    let path: String
    let lastUsed: Date
    let isDirectory: Bool
    let searchableName: CachedSearchableString

    // Convert to the UI model
    func toSearchResult() -> SearchResult {
        return SearchResult(
            id: id,
            name: name,
            path: path,
            icon: NSWorkspace.shared.icon(forFile: path),
            isDirectory: isDirectory
        )
    }
}
