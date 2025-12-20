import Foundation

/// A utility class for fuzzy matching strings, with specific optimizations for Chinese Pinyin.
class StringFuzzyMatcher {

    /// Checks if the target string matches the query using:
    /// 1. Case-insensitive substring match
    /// 2. Pinyin full match (if target contains Chinese)
    /// 3. Pinyin acronym match (if target contains Chinese)
    ///
    /// - Note: This performs on-the-fly conversion. For large static lists, use `CachedSearchableString`.
    static func isMatch(_ target: String, query: String) -> Bool {
        if query.isEmpty { return true }

        // 1. Fast path: Direct containment (Case Insensitive)
        if target.localizedStandardContains(query) {
            return true
        }

        // Optimization: Only attempt Pinyin if target has Chinese/Special chars AND query is likely Pinyin (ASCII)
        guard target.hasMultiByteCharacters, query.isAscii else {
            return false
        }

        // 2. Slow path: On-the-fly conversion
        let pinyin = target.pinyin
        let acronym = target.pinyinAcronym

        // Check Full Pinyin (e.g. "weixin" matches "Wei Xin")
        // We remove spaces from pinyin to allow "weixin" to match "Wei Xin"
        if pinyin.replacingOccurrences(of: " ", with: "").localizedStandardContains(query) {
            return true
        }

        // Check Acronym (e.g. "wx" matches "Wei Xin")
        if acronym.localizedStandardContains(query) {
            return true
        }

        return false
    }
}

// MARK: - Caching Wrapper

/// Use this struct to wrap strings in lists that don't change often (like App names).
/// It pre-calculates Pinyin to ensure O(1) matching speed during search.
struct CachedSearchableString {
    let original: String
    private let pinyin: String
    private let acronym: String
    private let hasPinyin: Bool

    init(_ string: String) {
        self.original = string
        if string.hasMultiByteCharacters {
            self.pinyin = string.pinyin.lowercased()
            self.acronym = string.pinyinAcronym.lowercased()
            self.hasPinyin = true
        } else {
            self.pinyin = ""
            self.acronym = ""
            self.hasPinyin = false
        }
    }

    func matches(_ query: String) -> Bool {
        // 1. Fast direct match
        if original.localizedStandardContains(query) { return true }

        // If no pinyin was calculated (because it was ASCII target), we are done
        if !hasPinyin { return false }

        let lowerQuery = query.lowercased()

        // 2. Check Acronym (e.g. query "wx" matches acronym "wx")
        if acronym.contains(lowerQuery) { return true }

        // 3. Check Full Pinyin (e.g. query "wei" matches pinyin "wei xin")
        if pinyin.replacingOccurrences(of: " ", with: "").contains(lowerQuery) { return true }

        return false
    }
}

// MARK: - Extensions

extension String {
    var hasMultiByteCharacters: Bool {
        // Simple heuristic: if utf8 count is different from character count, it likely has multibyte chars (like Emoji or Chinese)
        return self.utf8.count != self.count
    }

    var isAscii: Bool {
        return self.allSatisfy { $0.isASCII }
    }

    /// Converts "微信" to "Wei Xin"
    var pinyin: String {
        let mutableString = NSMutableString(string: self)
        // Convert to Latin (Pinyin)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        // Remove tone marks
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return String(mutableString)
    }

    /// Converts "微信" to "wx"
    var pinyinAcronym: String {
        let pinyinStr = self.pinyin
        let components = pinyinStr.components(separatedBy: " ")
        var acronym = ""
        for comp in components {
            if let first = comp.first {
                acronym.append(first)
            }
        }
        return acronym
    }
}
