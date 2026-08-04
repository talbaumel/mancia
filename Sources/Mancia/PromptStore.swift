import Foundation

enum PromptStore {
    enum StoreError: LocalizedError, Equatable {
        case documentsDirectoryUnavailable
        case missingDefaults
        case invalidLine(number: Int)
        case missingField(String)
        case duplicateFile(String)
        case invalidFile(String)
        case emptyPrompt(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "The Documents folder could not be found."
            case .missingDefaults:
                return "The bundled prompts folder could not be found."
            case .invalidLine(let number):
                return "Prompts YAML line \(number) is invalid."
            case .missingField(let field):
                return "A prompts YAML entry is missing \(field)."
            case .duplicateFile(let file):
                return "Prompts YAML lists \(file) more than once."
            case .invalidFile(let file):
                return "Prompt file \(file) must be a Markdown filename without a path."
            case .emptyPrompt(let file):
                return "Prompt file \(file) is empty."
            }
        }
    }

    private struct Entry {
        var file: String?
        var title: String?
        var symbol: String?
        var progress: String?
        var enabled = true
    }

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else { throw StoreError.documentsDirectoryUnavailable }
        return documents
            .appendingPathComponent("Mancia", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)
    }

    static func loadOrCreate(
        at directoryURL: URL? = nil,
        defaultsURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [PanelPreset] {
        let directory = try directoryURL ?? defaultURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: directory.path) {
            guard let defaults = defaultsURL ?? bundledDefaultsURL(fileManager: fileManager) else {
                throw StoreError.missingDefaults
            }
            try fileManager.createDirectory(
                at: directory.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try fileManager.copyItem(at: defaults, to: directory)
        }
        let manifestURL = directory.appendingPathComponent("prompts.yaml")
        let yaml = try String(contentsOf: manifestURL, encoding: .utf8)
        return try load(yaml: yaml, from: directory, fileManager: fileManager)
    }

    static func load(
        yaml: String,
        from directory: URL,
        fileManager: FileManager = .default
    ) throws -> [PanelPreset] {
        let entries = try parse(yaml)
        var seen = Set<String>()
        return try entries.compactMap { entry in
            guard entry.enabled else { return nil }
            guard let file = entry.file else { throw StoreError.missingField("file") }
            guard file.hasSuffix(".md"), URL(fileURLWithPath: file).lastPathComponent == file else {
                throw StoreError.invalidFile(file)
            }
            guard seen.insert(file).inserted else { throw StoreError.duplicateFile(file) }
            guard let title = entry.title else { throw StoreError.missingField("title") }
            guard let symbol = entry.symbol else { throw StoreError.missingField("symbol") }
            guard let progress = entry.progress else { throw StoreError.missingField("progress") }
            let prompt = try String(
                contentsOf: directory.appendingPathComponent(file), encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { throw StoreError.emptyPrompt(file) }
            return PanelPreset(
                id: String(file.dropLast(3)),
                title: title,
                action: .prompt(instruction: prompt, progressLabel: progress),
                symbol: symbol,
                progressLabel: progress)
        }
    }

    private static func parse(_ yaml: String) throws -> [Entry] {
        var entries: [Entry] = []
        var current: Entry?
        for (index, rawLine) in yaml.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), line != "prompts:" else { continue }
            let startsEntry = line.hasPrefix("- ")
            let fieldLine = startsEntry ? String(line.dropFirst(2)) : line
            guard let colon = fieldLine.firstIndex(of: ":") else {
                throw StoreError.invalidLine(number: index + 1)
            }
            if startsEntry {
                if let current { entries.append(current) }
                current = Entry()
            }
            guard current != nil else { throw StoreError.invalidLine(number: index + 1) }
            let key = fieldLine[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = fieldLine[fieldLine.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            let value = try scalar(rawValue, lineNumber: index + 1)
            switch key {
            case "file": current?.file = value
            case "title": current?.title = value
            case "symbol": current?.symbol = value
            case "progress": current?.progress = value
            case "enabled":
                guard value == "true" || value == "false" else {
                    throw StoreError.invalidLine(number: index + 1)
                }
                current?.enabled = value == "true"
            default: throw StoreError.invalidLine(number: index + 1)
            }
        }
        if let current { entries.append(current) }
        return entries
    }

    private static func scalar(_ raw: String, lineNumber: Int) throws -> String {
        if raw.hasPrefix("\"") || raw.hasSuffix("\"") {
            guard raw.hasPrefix("\""), raw.hasSuffix("\""),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(String.self, from: data)
            else { throw StoreError.invalidLine(number: lineNumber) }
            return decoded
        }
        return raw
    }

    private static func bundledDefaultsURL(fileManager: FileManager) -> URL? {
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("prompts", isDirectory: true),
           fileManager.fileExists(atPath: resourceURL.path)
        {
            return resourceURL
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("prompts", isDirectory: true)
        return fileManager.fileExists(atPath: sourceURL.path) ? sourceURL : nil
    }
}