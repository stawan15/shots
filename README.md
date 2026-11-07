# shots

[![CI](https://github.com/stawan15/shots/actions/workflows/ci.yml/badge.svg)](https://github.com/stawan15/shots/actions/workflows/ci.yml)

**Your screenshots, named and filed by what's actually in them.**

A macOS menu-bar app and CLI that reads each screenshot with on-device Vision OCR,
works out what it shows, gives it a descriptive filename, and files it into folders
by topic or by day. No filename archaeology, no manual renaming, no cloud.

<img src="docs/preview.png" width="360" alt="The Shots menu-bar popover showing two screenshots with thumbnails, new filenames, and topic badges">

```
before                                    after
Screenshot 2569-11-06 at 13.45.38.png  →  2026-11-06-1345-teams-meeting-devops-team-chat.png
Screenshot 2569-11-04 at 15.43.44.png  →  2026-11-04-1543-zabbix-current-value.png
Screenshot 2569-11-06 at 13.07.55.png  →  2026-11-06-1307-terminal-docker-ps-web-01.png
Screenshot 2569-11-05 at 14.12.01.png  →  2026-11-05-1412-grafana-team-kubernetes-node-exporter.png
```

Filed into `~/Screenshots/2026-11-06/`, or by topic, or both — your choice.

## Why

Screenshot folders rot. macOS calls everything `Screenshot 2026-11-06 at 13.45.38.png`,
so the only way to find the one Grafana panel you need is to open forty images. The
usual fix is a cloud AI service: an API key, an upload of your work screens, and a bill.

This does it locally. Apple's Vision framework already ships on every Mac with strong
OCR and image classification. Put a thin, opinionated layer on top — topic rules,
readable-title selection, safe file moves — and the folder organises itself.

Nothing leaves the machine. No network calls. No model download. It works on a plane.

## Install

Requires macOS 14+ and Swift 6 (CommandLineTools is enough — no Xcode needed).

```sh
git clone https://github.com/stawan15/shots.git
cd shots
./install.sh          # builds the CLI → ~/.local/bin/shots
./build-app.sh        # builds the menu-bar app → dist/Shots.app
```

## Use it

### Menu bar

```sh
open dist/Shots.app
```

The icon shows how many screenshots are waiting. Click it for thumbnails, the new
name for each shot, and the topic it was assigned. Uncheck anything you want to
leave alone, then **File All**. Settings covers watched folders, destination,
layout, and custom rules. Flip **File new screenshots automatically** and it keeps
up on its own.

### Command line

```sh
shots plan            # see every rename and move; touches nothing
shots apply --yes     # do it
shots undo            # put the last batch back, exactly as it was
```

Keep it running in the background:

```sh
shots watch --interval 20      # foreground loop
shots agent install            # or a launchd job that runs at login
```

## How it decides

1. **OCR** the image with Vision (accurate mode, English + Thai by default).
2. **Score topic rules** against the text. Each topic has weighted keywords, so
   `grafana` scores high while `datasource` adds a little. The best score wins —
   a JMeter page containing a Keycloak login URL is still filed under `testing`,
   not `auth`. Generic single keywords aren't enough; unclear shots go to `misc`
   rather than being mislabelled.
3. **Pick a title.** For terminal screenshots that's the command at the prompt
   (`docker ps web-01`). Otherwise it's the most readable line near the top —
   scored for real words, penalised for identifier soup, query strings, and
   OCR-mangled Thai.
4. **Slugify** to ASCII, dropping UI chrome (`search`, `dashboard`, `edit`), capped
   at 70 characters.

Built-in topics: monitoring (Grafana, Zabbix), testing (JMeter), ci-cd (GitHub
Actions, GitLab, Jenkins), auth (Keycloak), database (DBeaver, Postgres), chat
(Teams, Slack), docs (Confluence, Notion), terminal, errors, code, learning.

Capture time comes from the original filename, so it survives copies and mail
attachments, and the Thai Buddhist year is converted (`2569` → `2026`).

## Layouts

| `--layout` | Result |
| --- | --- |
| `day` (default) | `~/Screenshots/2026-11-06/2026-11-06-1345-grafana-cpu.png` |
| `topic` | `~/Screenshots/monitoring/2026-11-06-1345-grafana-cpu.png` |
| `both` | `~/Screenshots/monitoring/2026-11-06/2026-11-06-1345-grafana-cpu.png` |

## Teaching it your projects

`~/.config/shots/config.json` — your rules are checked first, and one keyword is
enough to match:

```json
{
  "sources": ["/Users/you/Desktop", "/Users/you/Downloads"],
  "destination": "/Users/you/Screenshots",
  "layout": "day",
  "languages": ["en-US", "th-TH"],
  "rules": [
    { "folder": "work/client-a", "tag": "clienta", "keywords": ["acme portal", "ticket 42"] }
  ]
}
```

```sh
shots config --edit
shots config --add-source ~/Downloads
shots config --layout topic
```

## Command reference

| Command | What it does |
| --- | --- |
| `shots plan` | Dry run: prints every source → destination, grouped by folder. |
| `shots apply --yes` | Performs the plan and writes an undo journal. |
| `shots undo` | Reverts the last batch, restoring original names and locations. Run again to go further back. |
| `shots list` | Past batches, newest first. |
| `shots watch` | Loop that files new screenshots. `--interval N`, min 5, default 30. |
| `shots agent install\|status\|log\|uninstall` | launchd job that runs `watch` at login. |
| `shots config [--print\|--edit\|--layout\|--add-source\|--destination]` | Read or change settings. |
| `shots debug PATH` | Dump OCR lines, Vision labels and the chosen name — for when a name looks wrong. |
| `shots version` | Version. |

Flags for `plan`, `apply`, `watch`:

| Flag | Meaning |
| --- | --- |
| `-d`, `--dir DIR` | Folder to scan. Repeatable. Defaults to the config's `sources`. |
| `--to DIR` | Destination root for this run only. |
| `--layout MODE` | `day`, `topic` or `both` for this run only. |
| `--all` | Also move images that don't look like screenshots. |
| `-y`, `--yes` | Required for `apply` to move anything. |
| `--json` | Plan as JSON, for scripting. |
| `-q`, `--quiet` | No progress output. |

The app also takes `--once` (scan, file, exit) and `--preview out.png` (render the
popover headlessly).

## Safety

Screenshots are work you can't regenerate, so the defaults are conservative:

- `plan` never touches files; `apply` requires `--yes`.
- Only files named `Screenshot …`, `CleanShot …`, `capture …` etc. are moved.
  `--all` opts other images in; photos then go to `images/`.
- Byte-identical duplicates are reported and left alone.
- Nothing is ever overwritten. Collisions get `-2`, `-3`, and a different candidate
  title is preferred over a numeric suffix when one exists.
- Every batch is journaled, so `undo` restores exact original names and paths.

## Where things live

| Path | Contents |
| --- | --- |
| `~/.config/shots/config.json` | Settings and custom rules. Shared by app and CLI. |
| `~/.local/share/shots/journal-*.json` | One per applied batch; `undo` consumes them. |
| `~/.local/share/shots/agent.log` | Output from the launchd job. |
| `~/Library/LaunchAgents/com.teveus.shots.plist` | The launchd job, if installed. |

## Development

```
Sources/ShotsCore/    engine: Vision analysis, naming, planning, journaling
Sources/shots/        CLI
Sources/ShotsApp/     menu-bar app (AppKit)
Sources/shots-selftest/  self-checks, since this toolchain has no XCTest
```

```sh
swift build -c release
swift run shots-selftest                        # routing and naming checks
swift run shots debug ~/Desktop/some-shot.png   # why was it named that?
.build/release/ShotsApp --preview /tmp/ui.png   # check UI layout without clicking
```

The app is AppKit rather than SwiftUI because a CommandLineTools-only toolchain
ships without SwiftUI's macro plugin, so `@State`/`@Published` fail to expand.
AppKit needs nothing extra and builds anywhere. With full Xcode installed,
`swift build` works unchanged.

Name lists live in `Sources/ShotsCore/Namer.swift`. Adding a topic is one entry:

```swift
Rule(folder: "infra", tag: "terraform",
     weighted: ["terraform apply": 5, "plan:": 2, "aws_": 2])
```

## License

MIT — see [LICENSE](LICENSE).
