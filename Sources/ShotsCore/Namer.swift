import Foundation

/// A naming rule: matched keywords pull a shot into `folder`; whichever rule
/// scores highest wins, so a JMeter page that also shows a Keycloak URL is still
/// a JMeter shot as long as its own evidence is stronger.
public struct Rule {
    public let folder: String
    public let tag: String
    public let keywords: [String: Int]
    public var pattern: String? = nil

    public init(folder: String, tag: String, keywords: [String], pattern: String? = nil) {
        self.folder = folder
        self.tag = tag
        self.pattern = pattern
        self.keywords = Dictionary(keywords.map { ($0, 2) }, uniquingKeysWith: { a, _ in a })
    }

    public init(folder: String, tag: String, weighted: [String: Int], pattern: String? = nil) {
        self.folder = folder
        self.tag = tag
        self.pattern = pattern
        self.keywords = weighted
    }

    func score(_ facts: ImageFacts) -> Int {
        var total = 0
        if let pattern, facts.text.range(of: pattern, options: [.regularExpression]) != nil {
            total += 3
        }
        for (keyword, weight) in keywords where facts.text.contains(keyword) {
            total += weight
        }
        return total
    }
}

public enum Namer {
    /// Ordered by specificity; ties are broken by this order.
    public static let builtinRules: [Rule] = [
        Rule(folder: "terminal", tag: "terminal",
             weighted: ["sudo ": 2, "~$ ": 2, "~ %": 2, "ssh ": 1, "docker ": 2,
                        "kubectl ": 2, "welcome to ubuntu": 4, "system information as of": 4,
                        "last login": 4, "ssh-ed25519": 4, "ssh-rsa": 4],
             pattern: #"(?m)^[a-z0-9._-]+@[a-z0-9.-]+[:~][^$\n]{0,40}\$\s"#),
        Rule(folder: "monitoring", tag: "grafana",
             weighted: ["grafana": 5, "home › dashboards": 4, "node_exporter": 3, "datasource": 1]),
        Rule(folder: "monitoring", tag: "zabbix", weighted: ["zabbix": 5, "check of pre-requisites": 3]),
        Rule(folder: "testing", tag: "jmeter",
             weighted: ["jmeter": 6, "view results tree": 3, "throughput": 1]),
        Rule(folder: "ci-cd", tag: "github-actions",
             weighted: ["github actions": 5, "jobs in run": 4, "workflow run": 3]),
        Rule(folder: "ci-cd", tag: "pipeline",
             weighted: ["gitlab": 4, "jenkins": 4, "pipeline stages": 3, "dependency scanning": 3]),
        Rule(folder: "auth", tag: "keycloak",
             weighted: ["realms/": 3, "openid-connect": 3, "single sign-on": 3, "client_id": 2]),
        Rule(folder: "database", tag: "dbeaver",
             weighted: ["dbeaver": 5, "sql editor": 3, "filter connections": 2]),
        Rule(folder: "database", tag: "postgres",
             weighted: ["postgres": 4, "psql": 3, "pg_stat": 3, "select * from": 2]),
        Rule(folder: "chat", tag: "teams",
             weighted: ["microsoft teams": 5, "team chat": 5, "meeting in": 4, "slack": 5,
                        "direct message": 4, "conversation": 1]),
        Rule(folder: "docs", tag: "docs",
             weighted: ["confluence": 5, "atlassian": 4, "notion": 3, "shared page notes": 3]),
        Rule(folder: "errors", tag: "error",
             weighted: ["privacy error": 5, "certificate": 2, "traceback": 3, "not secure": 3]),
        Rule(folder: "learning", tag: "learning",
             weighted: ["duolingo": 5, "intermediate": 2, "lesson": 2]),
        Rule(folder: "code", tag: "editor",
             weighted: ["extensions": 2, "package.json": 3, "src/": 1, "visual studio code": 4]),
    ]

    /// Words that are UI chrome, not content. Dropping them keeps slugs short.
    static let noise: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "are", "was", "were",
        "home", "dashboards", "dashboard", "edit", "add", "save", "cancel", "close",
        "search", "jump", "to", "not", "you", "your", "our", "all", "new", "open",
        "view", "click", "here", "more", "next", "back", "copy", "download", "share",
        "settings", "options", "help", "about", "version", "overview", "summary",
        "translate", "translat", "english", "thai", "language", "duration", "start",
        "date", "user", "users", "status", "https", "http", "www", "com", "local",
        "html", "welcome", "please", "select", "check", "loading", "total", "average",
        "usage", "system", "print", "filter", "button", "cancel", "ok",
        "enter", "address", "google", "tab", "send", "delete", "ctrl", "alt", "shift",
        "escape", "enter", "backspace", "paste", "undo", "redo", "bar", "pop", "out",
        "microsoft", "editor", "window", "menu", "file", "help", "pages",
    ]

    /// Function words are fine inside a title but never make it into a slug.
    static let stopwords: Set<String> = [
        "in", "on", "at", "of", "is", "it", "by", "as", "an", "or", "if", "no", "up", "we",
    ]

    public static func rule(for facts: ImageFacts, extra: [Rule]) -> Rule? {
        var best: (rule: Rule, score: Int)?
        for rule in extra + builtinRules {
            let score = rule.score(facts)
            if score > (best?.score ?? 0) {
                best = (rule, score)
            }
        }
        // One weak, generic keyword (e.g. "conversation") is not enough to file a
        // screenshot; better to leave it in misc than to mislabel it.
        guard let best, best.score >= 3 else { return nil }
        return best.rule
    }

    /// The command typed at a shell prompt, e.g. "docker ps" or "cat .ssh/authorized_keys".
    static func shellCommand(_ facts: ImageFacts) -> (command: String, host: String)? {
        let prompt = try! NSRegularExpression(
            pattern: #"^([a-z0-9._-]+)@([a-z0-9.-]+)[:~\w. -]{0,40}?[$#]\s+(.+)$"#,
            options: [.caseInsensitive])
        for line in facts.lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = prompt.firstMatch(in: line, options: [], range: range),
                  let commandRange = Range(match.range(at: 3), in: line),
                  let hostRange = Range(match.range(at: 2), in: line)
            else { continue }
            let command = String(line[commandRange]).trimmingCharacters(in: .whitespaces)
            if command.isEmpty { continue }
            return (command, String(line[hostRange]))
        }
        return nil
    }

    /// Best guess at the human-meaningful title of the screenshot: the densest
    /// readable line near the top of the image.
    static func title(for facts: ImageFacts, preferred: String?) -> String? {
        titles(for: facts, limit: 1, preferred: preferred).first
    }

    /// Ranked candidate titles. Callers that hit a name collision can fall back
    /// to the runner-up so near-identical screenshots still get distinct names.
    static func titles(for facts: ImageFacts, limit: Int, preferred: String?) -> [String] {
        if let shell = shellCommand(facts) {
            return ["\(shell.command) \(shell.host)"]
        }

        var scored: [(line: String, score: Double)] = []
        for raw in facts.lines.prefix(14) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().contains("http") { continue }
            // Query strings and URL fragments (response_type=code&client_id=…)
            // read as gibberish in a filename even though they OCR cleanly.
            if line.contains("=") && (line.contains("&") || line.contains("?")) { continue }
            if line.count > 90 { continue }
            if line.range(of: #"^[\d\s:./%()•-]+$"#, options: .regularExpression) != nil { continue }
            guard var score = readability(line) else { continue }
            // The line naming the app/topic is usually the best title
            // ("DBeaver 26.2.3 - staging" beats the window title above it).
            if let preferred, line.lowercased().contains(preferred) { score += 3 }
            scored.append((line, score))
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.line)
    }

    /// Rejects lines that are really identifiers, base64 keys or OCR noise, and
    /// scores the rest by how much real language they contain.
    static func readability(_ line: String) -> Double? {
        let words = tokenize(line)
        guard !words.isEmpty, words.count <= 11 else { return nil }
        var letters = 0
        var contentWords = 0
        var textualWords = 0
        for word in words {
            if word.count > 24 { return nil }
            let wordLetters = word.filter { $0.isLetter }.count
            letters += wordLetters
            guard wordLetters > 0 else { continue }   // versions, counts, IDs
            textualWords += 1
            if wordLetters >= 3, !noise.contains(word.lowercased()) { contentWords += 1 }
        }
        let digits = line.filter { $0.isNumber }.count
        guard letters >= 5,
              contentWords > 0,
              textualWords > 0,
              Double(digits) / Double(max(line.count, 1)) < 0.35,
              Double(contentWords) / Double(textualWords) >= 0.5
        else { return nil }

        // Vision mangles Thai glyphs into nonsense ASCII ("wu thn", "un nann"),
        // so prefer mostly-English lines when both are available.
        let ascii = line.unicodeScalars.filter { $0.isASCII }.count
        let asciiRatio = Double(ascii) / Double(max(line.unicodeScalars.count, 1))
        return Double(min(words.count, 6)) + Double(contentWords) * 0.5 + asciiRatio
    }

    static func tokenize(_ line: String) -> [String] {
        var split = line
        for separator in ["›", "|", "•", "·", "—", "–", "/", "\\", "(", ")", "[", "]",
                          ",", ".", ":", ";", "\"", "'", "?", "!", "+", "=", "%", "&", "#",
                          "@", "_", "$", ">", "<", "~", "^", "*", "{", "}", "\t"] {
            split = split.replacingOccurrences(of: separator, with: " ")
        }
        return split
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    static func slug(_ text: String, limit: Int = 5) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for word in tokenize(text.lowercased()) {
            // ASCII only: OCR mangles Thai, URLs and keys into unusable filenames.
            let clean = String(word.unicodeScalars.filter {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0)
            }.map(Character.init))
            guard clean.count > 1,
                  clean.contains(where: { $0.isLetter }),
                  !noise.contains(clean),
                  !stopwords.contains(clean),
                  !seen.contains(clean)
            else { continue }
            seen.insert(clean)
            out.append(clean)
            if out.count == limit { break }
        }
        return out.joined(separator: "-")
    }

    public struct Name {
        public let folder: String
        public let stem: String
    }

    /// Build the descriptive name for one screenshot. `attempt` picks the
    /// runner-up title, which the planner uses to break name collisions; it
    /// returns nil once the titles run out, so the caller can fall back to a
    /// numeric suffix instead of degrading the name to "screenshot".
    public static func name(for facts: ImageFacts, extra: [Rule], isCapture: Bool, attempt: Int = 0) -> Name? {
        let matched = rule(for: facts, extra: extra)
        let folder = matched?.folder ?? (isCapture ? "misc" : "images")
        var parts: [String] = []
        if let tag = matched?.tag { parts.append(tag) }

        // Slug every candidate up front and drop the ones that were nothing but
        // the tag, so "…-zabbix" falls through to a line with real content and
        // `attempt` indexes the list of usable subjects rather than raw lines.
        let bodies = titles(for: facts, limit: 6, preferred: matched?.tag).compactMap { title -> String? in
            var body = slug(title)
            // Avoid repeating the tag: "grafana grafana ..." -> "grafana ..."
            if let tag = matched?.tag, body.hasPrefix(tag) {
                body = String(body.dropFirst(tag.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }
            return body.isEmpty ? nil : body
        }
        // Running out of alternate titles means this image is a near-duplicate of
        // one already planned: report that instead of inventing a vague name.
        if attempt > 0, !bodies.indices.contains(attempt) { return nil }

        if bodies.indices.contains(attempt) {
            parts.append(bodies[attempt])
        }

        var stem = parts.joined(separator: "-")
        // Scene labels ("outdoor", "wood") describe photos, not UI captures, so
        // they only make a title when the file is not a screenshot.
        if stem.isEmpty, !isCapture, let scene = facts.sceneLabel {
            stem = slug(scene, limit: 3)
        }
        if stem.isEmpty {
            // No text to describe: dimensions at least tell you what it was.
            stem = isCapture
                ? "screenshot-\(facts.width)x\(facts.height)"
                : "image"
        }
        if stem.count > 70 {
            stem = String(stem.prefix(70)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return Name(folder: folder, stem: stem)
    }
}
