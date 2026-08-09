# PrettyTerm Beta

PrettyTerm is a lightweight native macOS companion for Claude Code sessions running in Apple Terminal. It reads local Claude Code transcripts, presents them in a focused conversation interface, and sends messages back to the exact Terminal session selected by the user.

> [!IMPORTANT]
> PrettyTerm is beta software. It is an independent community project and is not affiliated with or endorsed by Anthropic.

## Highlights

- Native AppKit interface with no full Xcode project required.
- Local session discovery from `~/.claude/projects`.
- Exact Terminal binding using TTY, process, and Claude session metadata checks.
- Markdown rendering for headings, lists, quotes, links, code blocks, and tables.
- Bundled MathJax rendering for inline and display LaTeX.
- Expandable thinking, tool, error, and line-by-line diff events.
- Inspector for connection state, context usage, plan limits, estimated API-equivalent cost, changed files, tasks, and an expandable repository diff.
- Remembered Git observation directories discovered from the selected Claude Code transcript, plus manually added directories.
- Always-on-top floating conversation window.
- Text and image composition shared by the main and floating windows.
- Light and dark appearance support.

## Requirements

- macOS 13 Ventura or later.
- Claude Code installed and running in Apple Terminal.
- Permission for PrettyTerm to automate Terminal when macOS requests it.

Building from source additionally requires the macOS Command Line Tools and Node.js for the JavaScript tests.

## Install a Release

1. Download the latest `PrettyTerm-Beta-*.dmg` from [Releases](https://github.com/starshipmiyabi/PrettyTerm/releases).
2. Open the disk image and drag `PrettyTerm Beta.app` to the **Applications** shortcut.
3. Start Claude Code in Apple Terminal.
4. Open PrettyTerm, choose a session, and click **Sync Terminal** before sending.

Because beta builds may use ad-hoc signing, macOS can request Terminal automation permission again after an update.

## Build from Source

```bash
git clone https://github.com/starshipmiyabi/PrettyTerm.git
cd PrettyTerm
./build-app.command
```

Local builds use ad-hoc signing by default, with Hardened Runtime and the minimum Apple Events entitlement enabled. For a distributable build with stable identity, provide an Apple-issued Developer ID Application identity:

```bash
PRETTYTERM_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.command
```

The application is written to:

```text
dist/PrettyTerm Beta.app
```

Run the complete validation suite with:

```bash
zsh Tests/verify.sh
```

Create the versioned DMG and `SHA256SUMS.txt` with:

```bash
./package-dmg.command
```

## How It Works

PrettyTerm watches Claude Code JSONL transcripts under `~/.claude/projects` and renders a read-only conversation snapshot in a local `WKWebView`. Active transcripts are parsed from their last completed byte offset, and newly appended messages are added without replacing the existing conversation DOM. Sending remains anchored to Apple Terminal: PrettyTerm validates the selected Claude PID, TTY, exact process name, and session before writing to the bound tab.

PrettyTerm does not replace Claude Code or run a separate agent service. Claude.ai Remote Control is intentionally disabled.

## Git Inspector and Directory Scope

The inspector can widen on demand to show the selected repository's local Git status and diff. PrettyTerm supports two sources for Git observation directories:

- **Observed directories:** PrettyTerm collects absolute `cwd` values found in the selected Claude Code transcript and remembers them locally for later selection. This reflects directories recorded while Claude Code works, including paths seen after Claude Code has used an added directory.
- **Manual directories:** Enter an absolute folder path in the inspector to add it directly to PrettyTerm's remembered Git directory list.

Both controls only change where PrettyTerm runs its read-only Git probes. They do not change Claude Code's working directory, grant Claude Code access to a folder, send terminal input, or execute a Claude Code command. To let Claude Code access another folder, run `/add-dir /absolute/path` inside Claude Code itself. PrettyTerm can then remember transcript directories that Claude Code records while working.

The diff panel shows tracked changes relative to `HEAD` and lists untracked files in the status section. Large output is truncated locally to keep the interface responsive.

## Privacy and Network Access

- Conversation transcripts are read from the local machine.
- PrettyTerm does not upload transcript contents to its own server.
- The plan-usage panel reads the `Claude Code-credentials` item through macOS Security APIs under PrettyTerm's own code identity. It does not invoke `/usr/bin/security` or print the credential.
- The access token is sent only as authorization for Anthropic's authenticated Claude usage endpoint to display the current 5-hour and 7-day limits.
- The conversation WebView blocks network connections with Content Security Policy; bundled MathJax cannot dynamically load `require` or `autoload` extensions.
- API-equivalent cost is an estimate based on transcript usage data and public API pricing; it is not a subscription charge.

## Current Limitations

- Apple Terminal is currently the only supported terminal application.
- PrettyTerm must sync to a live Claude Code process before it can send.
- Some slash commands and terminal-only workflows are best executed directly in Terminal.
- Beta builds are not notarized.

## Project Layout

```text
Sources/       Native Objective-C application code
Resources/     Conversation renderer, MathJax bundle, and app artwork
Tests/         Native and JavaScript regression tests
Info.plist     Bundle metadata and release version
PrettyTerm.entitlements
build-app.command
package-dmg.command
```

## Contributing

Bug reports and focused pull requests are welcome. Please include the macOS version, Claude Code version, PrettyTerm version shown in the top-left corner, and exact reproduction steps. Never attach private transcripts, credentials, or session metadata to a public issue.

## License

PrettyTerm is available under the [MIT License](LICENSE).

## Disclaimer

Claude and Claude Code are trademarks of Anthropic. PrettyTerm is an unofficial companion application.
