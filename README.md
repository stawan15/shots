# shots

Files your macOS screenshots by *what is in them*, not by timestamp. Everything
runs on-device with Apple's Vision framework: no API keys, no uploads, nothing
leaves the machine.

```
~/Screenshots/
  2026-11-04/
    2026-11-04-1341-grafana-team-kubernetes-node-exporter.png
    2026-11-04-1543-zabbix-current-value.png
  2026-11-05/
    2026-11-05-1153-error-net-err-cert-authority-invalid.png
  2026-11-06/
    2026-11-06-1307-terminal-docker-ps-web-01.png
    2026-11-06-1345-teams-meeting-devops-team-chat.png
```

## Install

```sh
./install.sh          # builds and copies to ~/.local/bin/shots
```

## Use

```sh
shots plan            # dry run: prints the full rename/move table, moves nothing
shots apply --yes     # do it
shots undo            # put the last batch back exactly where it was
shots list            # previous batches
```

Watch mode files new screenshots as they appear (every 30s by default):

```sh
shots watch --interval 20
```

Or run that automatically at login:

```sh
shots agent install    # launchd job, checks once a minute
shots agent status
shots agent uninstall
```

## How it decides

1. **OCR** every image with Vision (`accurate`, English + Thai).
2. **Score topic rules** against the extracted text — `grafana`, `keycloak`,
   `jmeter`, `github actions`, `dbeaver`, `zabbix`, shell prompts, and so on.
   The highest score wins, so a JMeter page that contains a Keycloak URL is still
   filed under `testing`. A single weak generic keyword is not enough; those
   screenshots land in `misc` rather than being mislabelled.
3. **Pick a title** — for shell screenshots the command at the prompt
   (`docker ps web-01`), otherwise the most readable line near the top of the
   image. Identifier soup, base64 and OCR-mangled Thai are scored down.
4. **Slugify** into ASCII, stripping UI chrome words (`search`, `dashboard`,
   `settings`), capping the name at 70 characters.

Filenames keep the capture time from the original name, so they survive copies,
and the Thai Buddhist year is converted (`2569` → `2026`).

## Layout

`--layout` (or `shots config --layout …`):

| mode | result |
| --- | --- |
| `day` (default) | `~/Screenshots/2026-11-06/2026-11-06-1345-grafana-cpu.png` |
| `topic` | `~/Screenshots/monitoring/2026-11-06-1345-grafana-cpu.png` |
| `both` | `~/Screenshots/monitoring/2026-11-06/2026-11-06-1345-grafana-cpu.png` |

## Config

`~/.config/shots/config.json` (`shots config --edit`):

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

Your own rules are checked first and one keyword is enough to match, so a single
line of JSON teaches the tool a new project:

```sh
shots config --add-source ~/Downloads
shots config --layout topic
```

## Safety

- `plan` never touches files; `apply` requires `--yes`.
- Only files named `Screenshot …` / `CleanShot …` / `capture …` are moved by
  default. `--all` opts other images in.
- Byte-identical duplicates are reported and left in place.
- Nothing is ever overwritten: collisions become `-2`, `-3`, and a second
  candidate title is preferred over a numeric suffix when one exists.
- Every applied batch is journaled in `~/.local/share/shots/`, so `shots undo`
  restores exact original names and locations.
- Photos on the Desktop are left alone and, if you pass `--all`, go to `images/`.

## Development

```sh
swift build -c release
swift run shots-selftest     # 17 checks over routing and naming
swift run shots debug ~/Desktop/some-shot.png   # OCR dump + why it was named that way
```
