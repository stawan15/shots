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
shots agent log        # what it has filed lately
shots agent uninstall
```

## Full command reference

| Command | What it does |
| --- | --- |
| `shots plan` | Dry run. Prints every source → destination, groups by folder. Accepts all the flags below. |
| `shots apply --yes` | Performs the plan and writes an undo journal. Without `--yes` it only prints what it would move. |
| `shots undo` | Reverts the most recent batch, restoring original filenames and locations, then deletes that journal entry. Run it repeatedly to walk back further. |
| `shots list` | Lists past batches, newest first. |
| `shots watch` | Long-running loop that files new screenshots. `--interval N` seconds between checks (min 5, default 30). Files are left alone for 5s after capture so the screenshot tool can finish writing. |
| `shots agent install` | Installs a launchd job (`~/Library/LaunchAgents/com.teveus.shots.plist`) that runs `watch --interval 60` at login. |
| `shots agent status` | Shows whether the job is installed and its launchd state. |
| `shots agent log` | Tails the last 40 lines of the agent's log. |
| `shots agent uninstall` | Boots the job out and deletes the plist. |
| `shots config` | Prints the current config. |
| `shots config --edit` | Opens `~/.config/shots/config.json` in `$EDITOR`. |
| `shots config --layout day\|topic\|both` | Sets the default layout. |
| `shots config --add-source DIR` | Adds a folder to scan (`--remove-source DIR` to drop it). |
| `shots config --destination DIR` | Changes the destination root. |
| `shots config --print` | Prints the config after applying any other config flags given on the same line. |
| `shots debug PATH` | Dumps OCR lines, Vision labels, and the resulting name for one file. Use this when a name looks wrong. |
| `shots version` | Prints the version. |

### Flags (for `plan`, `apply`, `watch`)

| Flag | Meaning |
| --- | --- |
| `-d`, `--dir DIR` | Folder to scan. Repeatable. Defaults to `sources` in the config. |
| `--to DIR` | Destination root for this run only (does not change the config). |
| `--layout MODE` | `day`, `topic` or `both` for this run only. |
| `--all` | Also move images that do not look like screenshots (photos, exported diagrams). |
| `-y`, `--yes` | Required for `apply` to actually move files. |
| `--json` | Emit the plan as JSON (source, destination, folder, created). Useful for scripting; `apply --json` still applies. |
| `-q`, `--quiet` | No progress output. |

### Common recipes

```sh
# see what would happen, then do it
shots plan && shots apply --yes

# organise a different folder once, into a scratch tree
shots plan  --dir ~/Pictures/inbox --to ~/Screenshots/inbox
shots apply --dir ~/Pictures/inbox --to ~/Screenshots/inbox --yes

# keep it automatic
shots agent install

# something got named badly — find out why
shots debug ~/Screenshots/2026-11-06/*docker*.png

# a new project you want recognised
shots config --edit      # add {"folder":"work/client-a","tag":"clienta","keywords":["acme portal"]}
```

### Where things live

| Path | Contents |
| --- | --- |
| `~/.local/bin/shots` | The binary (installed by `install.sh`). |
| `~/.config/shots/config.json` | Sources, destination, layout, language list, your custom rules. |
| `~/.local/share/shots/journal-*.json` | One file per applied batch. `shots undo` consumes these. |
| `~/Library/LaunchAgents/com.teveus.shots.plist` | The background job, if installed. |
| `~/.local/share/shots/agent.log` | Output from the background job. |

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
