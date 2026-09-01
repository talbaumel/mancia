import Foundation

/// Corrects text typed with the English or Hebrew keyboard layout selected by
/// mistake. Direction is inferred from the characters that belong uniquely to
/// each layout; characters outside the keyboard map are preserved.
enum KeyboardLayoutConverter {
    enum Language: Equatable, Sendable {
        case english, hebrew

        var languageCode: String {
            switch self {
            case .english: "en"
            case .hebrew: "he"
            }
        }
    }

    struct Conversion: Equatable, Sendable {
        let text: String
        let language: Language
    }

    private static let englishKeys = Array("`qwertyuiop[]\\asdfghjkl;'zxcvbnm,./")
    private static let hebrewKeys = Array(";/׳קראטוןםפ][\\שדגכעיחלךף,זסבהנמצתץ.")

    private static let englishToHebrew = Dictionary(
        uniqueKeysWithValues: zip(englishKeys, hebrewKeys))

    private static let hebrewToEnglish: [Character: Character] = {
        var mapping = Dictionary(uniqueKeysWithValues: zip(hebrewKeys, englishKeys))
        // Some apps produce an ASCII apostrophe for the Hebrew W key.
        mapping["'"] = "w"
        // Unambiguous output from Shift-modified keys in macOS's Hebrew layout.
        mapping["שׁ"] = "A"
        mapping["„"] = "D"
        mapping["וֹ"] = "U"
        mapping["״"] = "\""
        mapping["₪"] = "&"
        return mapping
    }()

    static func convert(_ text: String) -> String {
        conversion(of: text).text
    }

    static func conversion(of text: String) -> Conversion {
        let hebrewScore = text.reduce(into: 0) { score, character in
            if hebrewToEnglish[character] != nil, englishToHebrew[character] == nil {
                score += 1
            }
        }
        let englishScore = text.reduce(into: 0) { score, character in
            let lowercased = Character(String(character).lowercased())
            if englishToHebrew[lowercased] != nil, hebrewToEnglish[character] == nil {
                score += 1
            }
        }

        if hebrewScore > englishScore {
            return Conversion(
                text: String(text.map { hebrewToEnglish[$0] ?? $0 }),
                language: .english)
        }
        return Conversion(
            text: String(text.map { character in
                let lowercased = Character(String(character).lowercased())
                return englishToHebrew[lowercased] ?? character
            }),
            language: .hebrew)
    }
}