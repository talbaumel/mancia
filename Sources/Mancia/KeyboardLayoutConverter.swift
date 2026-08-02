import Foundation

/// Corrects text typed with the English or Hebrew keyboard layout selected by
/// mistake. Direction is inferred from the characters that belong uniquely to
/// each layout; characters outside the keyboard map are preserved.
enum KeyboardLayoutConverter {
    private static let englishKeys = Array("`qwertyuiop[]\\asdfghjkl;'zxcvbnm,./")
    private static let hebrewKeys = Array(";/׳קראטוןםפ][\\שדגכעיחלךף,זסבהנמצתץ.")

    private static let englishToHebrew = Dictionary(
        uniqueKeysWithValues: zip(englishKeys, hebrewKeys))

    private static let hebrewToEnglish: [Character: Character] = {
        var mapping = Dictionary(uniqueKeysWithValues: zip(hebrewKeys, englishKeys))
        // Some apps produce an ASCII apostrophe for the Hebrew W key.
        mapping["'"] = "w"
        return mapping
    }()

    static func convert(_ text: String) -> String {
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
            return String(text.map { hebrewToEnglish[$0] ?? $0 })
        }
        return String(text.map { character in
            let lowercased = Character(String(character).lowercased())
            return englishToHebrew[lowercased] ?? character
        })
    }
}