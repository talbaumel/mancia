import Foundation

struct TextSnippet: Equatable, Identifiable, Sendable {
    let title: String
    let value: String

    var id: String { title }
}

enum SnippetStore {
    enum StoreError: LocalizedError {
        case documentsDirectoryUnavailable
        case invalidLine(number: Int)
        case emptyKey(number: Int)
        case emptyValue(number: Int)
        case duplicateKey(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "The Documents folder could not be found."
            case .invalidLine(let number):
                return "Snippets YAML line \(number) must be `name: value`."
            case .emptyKey(let number):
                return "Snippets YAML line \(number) has an empty name."
            case .emptyValue(let number):
                return "Snippets YAML line \(number) has an empty value."
            case .duplicateKey(let key):
                return "Snippets YAML contains the name “\(key)” more than once."
            }
        }
    }

    static let mockContents = """
    # Mancia snippets. Values are pasted exactly as written.
    My wife ID: "123456789"
    My ID: "987654321"
    Office code: "246810"
    """

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else { throw StoreError.documentsDirectoryUnavailable }
        return documents
            .appendingPathComponent("Mancia", isDirectory: true)
            .appendingPathComponent("snippets.yaml", isDirectory: false)
    }

    static func loadOrCreate(
        at url: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [TextSnippet] {
        let fileURL = try url ?? defaultURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: fileURL.path) {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try Data(mockContents.utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path)
        }
        return try parse(String(contentsOf: fileURL, encoding: .utf8))
    }

    static func parse(_ yaml: String) throws -> [TextSnippet] {
        var snippets: [TextSnippet] = []
        var seen = Set<String>()

        for (index, rawLine) in yaml.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                throw StoreError.invalidLine(number: lineNumber)
            }

            let rawKey = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            let key = try scalar(rawKey, lineNumber: lineNumber)
            let value = try scalar(rawValue, lineNumber: lineNumber)
            guard !key.isEmpty else { throw StoreError.emptyKey(number: lineNumber) }
            guard !value.isEmpty else { throw StoreError.emptyValue(number: lineNumber) }
            guard seen.insert(key).inserted else { throw StoreError.duplicateKey(key) }
            snippets.append(TextSnippet(title: key, value: value))
        }
        return snippets
    }

    private static func scalar(_ raw: String, lineNumber: Int) throws -> String {
        if raw.hasPrefix("\"") || raw.hasSuffix("\"") {
            guard raw.hasPrefix("\""), raw.hasSuffix("\""),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(String.self, from: data)
            else { throw StoreError.invalidLine(number: lineNumber) }
            return decoded
        }
        if raw.hasPrefix("'") || raw.hasSuffix("'") {
            guard raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'")
            else { throw StoreError.invalidLine(number: lineNumber) }
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }
}