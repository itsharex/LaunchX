import AppKit
import Combine
import Foundation

/// Coordinates the high-level search logic, delegating the heavy lifting to MetadataQueryService.
class FileSearchService: ObservableObject {
    // Publishes results to the ViewModel
    let resultsSubject = PassthroughSubject<[SearchResult], Never>()

    private let metadataService = MetadataQueryService.shared

    init() {
        // Start indexing immediately upon initialization with default config.
        // In a real app, you might load this config from UserDefaults.
        let config = SearchConfig()
        metadataService.startIndexing(with: config)
    }

    /// Performs a high-speed in-memory search
    func search(query text: String) {
        guard !text.isEmpty else {
            resultsSubject.send([])
            return
        }

        // Delegate to the in-memory index service
        // This is extremely fast (microseconds/milliseconds)
        let indexItems = metadataService.search(text: text)

        // Map internal IndexItems to UI SearchResults
        let results = indexItems.map { $0.toSearchResult() }

        resultsSubject.send(results)
    }

    /// Triggers a re-index if settings change (e.g. user adds a new folder)
    func updateConfig(_ config: SearchConfig) {
        metadataService.startIndexing(with: config)
    }
}
