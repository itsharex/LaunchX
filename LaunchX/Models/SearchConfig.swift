import Foundation

struct SearchConfig: Codable, Equatable {
    /// Default standard scopes
    static let defaultScopes: [String] = [
        "/Applications",
        "/System/Applications",
        NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? "",
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "",
        NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? "",
    ]

    /// Default excluded folder names
    static let defaultExcludedNames: [String] = [
        "node_modules",
        ".git",
        ".idea",
        ".vscode",
        "dist",
        "build",
        "target",
        "vendor",
        "Library",  // Usually we don't want to search inside ~/Library
    ]

    /// Paths to include in search (e.g., ~/Downloads, /Applications)
    var searchScopes: [String]

    /// Specific full paths to exclude
    var excludedPaths: [String]

    /// Folder names to exclude globally (e.g., node_modules)
    var excludedNames: [String]

    init(
        searchScopes: [String] = SearchConfig.defaultScopes,
        excludedPaths: [String] = [],
        excludedNames: [String] = SearchConfig.defaultExcludedNames
    ) {
        self.searchScopes = searchScopes
        self.excludedPaths = excludedPaths
        self.excludedNames = excludedNames
    }
}
