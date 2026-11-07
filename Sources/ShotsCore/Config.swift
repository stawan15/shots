import Foundation

public struct Config: Codable {
    /// Folders scanned and organised by default.
    public var sources: [String]
    /// Root folder that receives the organised tree.
    public var destination: String
    /// "day" -> 2026-11-06/1431-grafana-cpu.png
    /// "topic" -> monitoring/2026-11-06-1431-grafana-cpu.png
    public var layout: String
    public var languages: [String]
    /// Extra naming rules, checked before the built-in ones.
    public var rules: [RuleConfig]

    public struct RuleConfig: Codable {
        var folder: String
        var tag: String
        var keywords: [String]
    }

    public static var defaultPath: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(".config/shots/config.json")
    }

    public static func load() -> Config {
        let path = defaultPath
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return .init() }
        return config
    }

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sources = ["\(home)/Desktop", "\(home)/Downloads"]
        self.destination = "\(home)/Screenshots"
        self.layout = "day"
        self.languages = ["en-US", "th-TH"]
        self.rules = []
    }

    public var extraRules: [Rule] {
        // A user who writes a keyword means it: one match is enough to route.
        rules.map {
            Rule(
                folder: $0.folder,
                tag: $0.tag,
                weighted: Dictionary($0.keywords.map { ($0, 3) }, uniquingKeysWith: { a, _ in a }))
        }
    }

    public func save() throws {
        let path = Config.defaultPath
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: path)
    }
}
