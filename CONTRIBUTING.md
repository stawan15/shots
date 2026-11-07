# Contributing

Thanks for taking a look. This is a small tool; the bar for changes is "does it make
filing screenshots more reliably correct?"

## Getting set up

macOS 14+ and Swift 6. CommandLineTools is enough — you do not need Xcode.

```sh
git clone https://github.com/stawan15/shots.git
cd shots
swift build -c release
swift run shots-selftest
```

## Before opening a PR

```sh
swift build -c release
swift run shots-selftest      # must stay green
```

If you touched the UI, check it renders:

```sh
.build/release/ShotsApp --preview /tmp/ui.png
```

## Where things are

| Path | Role |
| --- | --- |
| `Sources/ShotsCore/Analyzer.swift` | Vision OCR and classification |
| `Sources/ShotsCore/Namer.swift` | Topic rules and filename construction |
| `Sources/ShotsCore/Library.swift` | Scanning, planning, applying, journal/undo |
| `Sources/ShotsCore/Config.swift` | `~/.config/shots/config.json` |
| `Sources/shots/main.swift` | CLI |
| `Sources/ShotsApp/` | Menu-bar app |

## Adding a topic

Most useful contributions are new topic rules. Each rule is a folder, a filename
tag, and weighted keywords:

```swift
Rule(folder: "infra", tag: "terraform",
     weighted: ["terraform apply": 5, "plan:": 2, "aws_": 2])
```

Weights matter. Put a strong, unambiguous string at 4–6 and supporting evidence at
1–3. Keep the total for a coincidental match below 3, which is the threshold for
routing at all — a screenshot that merely mentions a word should stay in `misc`
instead of being mislabelled.

Add a check for it in `Sources/shots-selftest/main.swift` so the behaviour is
pinned:

```swift
let terraform = facts(["terraform apply", "Apply complete! Resources: 3 added"])
expect(named(terraform, "terraform").folder == "infra", "terraform routes to infra")
```

## Style

- Match the surrounding code: small functions, comments that explain *why* rather
  than what, no comment on every line.
- Keep the engine in `ShotsCore` and UI concerns out of it, so the CLI and the app
  stay in lockstep.
- No network calls. This project's whole point is that your screens stay on your
  machine.

## Reporting a bad filename

Run:

```sh
shots debug path/to/the/image.png
```

That prints the OCR lines, Vision labels and the name it chose. Paste that into the
issue — it is usually enough to see whether a rule needs a keyword or the title
scorer needs adjusting. Please redact anything sensitive from the OCR dump.
