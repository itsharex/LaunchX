import AppKit
import Combine
import Foundation

/// Coordinates the high-level search logic, delegating the heavy lifting to MetadataQueryService.
class FileSearchService: ObservableObject {
    // Publishes results to the ViewModel (kept for compatibility)
    let resultsSubject = PassthroughSubject<[SearchResult], Never>()

    private let metadataService = MetadataQueryService.shared

    init() {
        // Start indexing immediately upon initialization with default config.
        let config = SearchConfig()
        metadataService.startIndexing(with: config)
    }

    /// Performs an async search via MetadataQueryService with completion handler
    func search(query text: String, completion: @escaping ([SearchResult]) -> Void) {
        guard !text.isEmpty else {
            completion([])
            return
        }

        metadataService.search(text: text) { indexItems in
            let results = indexItems.map { $0.toSearchResult() }
            completion(results)
        }
    }

    /// Legacy method for compatibility
    func search(query text: String) {
        search(query: text) { [weak self] results in
            self?.resultsSubject.send(results)
        }
    }

    /// Triggers a re-index if settings change (e.g. user adds a new folder)
    func updateConfig(_ config: SearchConfig) {
        metadataService.startIndexing(with: config)
    }
}
