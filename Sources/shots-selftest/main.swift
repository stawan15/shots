import Foundation
import ShotsCore

/// Minimal test runner. The CommandLineTools-only toolchain on this machine has
/// no XCTest, so `swift run shots-selftest` is the check to run instead.
var failures = 0
var checks = 0

func expect(_ condition: Bool, _ label: String, file: String = #file, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(label)  (\(file.split(separator: "/").last ?? ""):\(line))")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("  ✗ \(label): got \(actual), expected \(expected)  (line \(line))")
    }
}

func facts(
    _ lines: [String],
    screenshot: Bool = true,
    name: String = "Screenshot 2026-11-06 at 13.45.38.png"
) -> ImageFacts {
    ImageFacts(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        width: 3024,
        height: 1964,
        lines: lines,
        classes: [Classification(label: "screenshot", confidence: 0.9)],
        isScreenshot: screenshot,
        creationDate: Date(timeIntervalSince1970: 1_791_000_000))
}

func group(_ title: String) { print("\n\(title)") }

/// Fails the run instead of crashing when a name is unexpectedly nil.
func named(
    _ facts: ImageFacts, _ label: String,
    extra: [Rule] = [], isCapture: Bool = true, attempt: Int = 0, line: Int = #line
) -> Namer.Name {
    guard let name = Namer.name(
        for: facts, extra: extra, isCapture: isCapture, attempt: attempt)
    else {
        failures += 1
        checks += 1
        print("  ✗ \(label): expected a name, got nil  (line \(line))")
        // Keep going so the remaining checks still run.
        return Namer.name(
            for: ImageFacts(
                url: URL(fileURLWithPath: "/tmp/fallback.png"), width: 1, height: 1,
                lines: ["Fallback title"], classes: [], isScreenshot: true,
                creationDate: Date()),
            extra: [], isCapture: true)!
    }
    return name
}

group("routing")

let grafana = facts([
    "Home › Dashboards",
    "Team - Kubernetes Views / Global",
    "CPU usage",
])
var name = named(grafana, "grafana", extra: [], isCapture: true)
equal(name.folder, "monitoring", "grafana goes to monitoring")
expect(name.stem.hasPrefix("grafana"), "grafana tag prefixes the name: \(name.stem)")

let jmeter = facts([
    "View Results Tree",
    "jmeter1.internal.example",
    "sso.example.com/realms/app/protocol/openid-connect/auth",
    "Throughput 12.4/sec",
])
name = named(jmeter, "jmeter", extra: [], isCapture: true)
equal(name.folder, "testing", "jmeter beats the Keycloak URL it embeds")

let keycloak = facts([
    "Sign in to your account",
    "https://sso.example.com/realms/app/protocol/openid-connect/auth",
    "Username",
])
name = named(keycloak, "keycloak", extra: [], isCapture: true)
equal(name.folder, "auth", "login page goes to auth")

let shell = facts([
    "deploy@web-01:~$ docker exec -it app cat /etc/app.conf",
    "sudo apt update",
])
name = named(shell, "shell", extra: [], isCapture: true)
equal(name.folder, "terminal", "shell prompt goes to terminal")
expect(name.stem.contains("docker"), "shell command becomes the name: \(name.stem)")

let unknown = facts(["Random wallpaper texture"])
name = named(unknown, "unknown", extra: [], isCapture: true)
equal(name.folder, "misc", "unrecognised capture falls back to misc")

let photo = facts(["Golden Gate Bridge at sunset"], screenshot: false)
name = named(photo, "photo", extra: [], isCapture: false)
equal(name.folder, "images", "non-capture image goes to images")
expect(!name.stem.isEmpty, "photo still gets a name")

group("filenames")

let noisy = facts(["Search  Dashboard  ถ่ายภาพ  cpu-overview"])
name = named(noisy, "noisy", extra: [], isCapture: true)
expect(!name.stem.contains("dashboard"), "UI chrome is stripped: \(name.stem)")
expect(!name.stem.contains(" "), "no spaces in the slug")
expect(!name.stem.contains("ถ"), "non-ASCII is dropped")

let long = facts(["This is an extremely long line of text about something in the dashboard view"])
name = named(long, "long", extra: [], isCapture: true)
expect(name.stem.count <= 70, "slug is capped at 70 characters: \(name.stem.count)")

group("rules and collisions")

let custom = Rule(folder: "work/client-a", tag: "clienta", weighted: ["acme ticket": 3])
let acme = facts(["ACME ticket 4211", "Search Dashboard"])
name = named(acme, "acme", extra: [custom], isCapture: true)
equal(name.folder, "work/client-a", "user rules win over built-ins")
expect(name.stem.hasPrefix("clienta"), "user tag prefixes the name: \(name.stem)")

let dashboards = facts([
    "Home › Dashboards",
    "Team - Kubernetes Views / Global",
    "Node exporter overview",
    "CPU usage panel",
])
let first = Namer.name(for: dashboards, extra: [], isCapture: true)!
let second = Namer.name(for: dashboards, extra: [], isCapture: true, attempt: 1)!
expect(first.stem != second.stem, "collision fallback picks another title: \(first.stem) vs \(second.stem)")

let weak = facts(["conversation"])
let weakName = Namer.name(for: weak, extra: [], isCapture: true)
name = weakName ?? named(facts(["weak fallback"]), "weak")
expect(Namer.rule(for: weak, extra: []) == nil, "a single weak keyword is not enough to route")

group("content hashing")

// FIPS 180-4 vectors: duplicate detection is only as good as the hash.
let vectors: [(String, String)] = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
]
for (input, expected) in vectors {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("shots-hash-\(UUID().uuidString).bin")
    try? Data(input.utf8).write(to: url)
    equal(Shots.contentHash(url) ?? "nil", expected, "sha256 of \(input.count) bytes")
    try? FileManager.default.removeItem(at: url)
}

// One megabyte of 'a' crosses many blocks and catches length-encoding bugs.
let big = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("shots-hash-big-\(UUID().uuidString).bin")
try? Data(repeating: 0x61, count: 1_000_000).write(to: big)
equal(Shots.contentHash(big) ?? "nil",
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
      "sha256 of 1 MB")
try? FileManager.default.removeItem(at: big)

group("versions")

// The updater refuses to install anything older than what is running, so these
// comparisons decide whether a release is offered at all.
expect(SemanticVersion("1.2.0") > SemanticVersion("1.1.0"), "1.2.0 is newer than 1.1.0")
expect(SemanticVersion("1.10.0") > SemanticVersion("1.9.0"), "numeric, not string, comparison")
expect(SemanticVersion("v1.2.0") == SemanticVersion("1.2.0"), "leading v is ignored")
expect(SemanticVersion("1.2.0-b2") < SemanticVersion("1.2.0"), "pre-release sorts before release")
expect(SemanticVersion("1.2") == SemanticVersion("1.2.0"), "missing patch is zero")
expect(SemanticVersion("1.2.0") == SemanticVersion("1.2.0"), "same version compares equal")
expect(!(SemanticVersion("1.1.0") > SemanticVersion("1.1.0")), "never offers the same version")
expect(SemanticVersion("2.0.0-beta") > SemanticVersion("1.9.9"), "major bumps outrank everything")
equal(SemanticVersion("1.2.3").description, "1.2.3", "description round trip")
equal(SemanticVersion("v1.2.3-rc1").description, "1.2.3-rc1", "description keeps pre-release")

print("")
if failures == 0 {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures) of \(checks) checks failed")
    exit(1)
}
