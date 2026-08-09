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
- Inspector for connection state, context usage, plan limits, estimated API-equivalent cost, changed files, and tasks.
- Always-on-top floating conversation window.
- Text and image composition shared by the main and floating windows.
- Light and dark appearance support.

## Requirements

- macOS 13 Ventura or later.
- Claude Code installed and running in Apple Terminal.
- Permission for PrettyTerm to automate Terminal when macOS requests it.

Building from source additionally requires the macOS Command Line Tools and Node.js for the JavaScript tests.

## Install a Release

1. Download the latest `PrettyTerm-Beta-*.app.zip` from [Releases](https://github.com/starshipmiyabi/PrettyTerm/releases).
2. Extract the archive and move `PrettyTerm Beta.app` to `/Applications`.
3. Start Claude Code in Apple Terminal.
4. Open PrettyTerm, choose a session, and click **Sync Terminal** before sending.

Because beta builds may use ad-hoc signing, macOS can request Terminal automation permission again after an update.

## Build from Source

```bash
git clone https://github.com/starshipmiyabi/PrettyTerm.git
cd PrettyTerm
./build-app.command
```

The application is written to:

```text
dist/PrettyTerm Beta.app
```

Run the complete validation suite with:

```bash
zsh Tests/verify.sh
```

## How It Works

PrettyTerm watches Claude Code JSONL transcripts under `~/.claude/projects` and renders a read-only conversation snapshot in a local `WKWebView`. Sending remains anchored to Apple Terminal: PrettyTerm validates the selected Claude process and session before writing to the bound tab.

PrettyTerm does not replace Claude Code or run a separate agent service. Claude.ai Remote Control is intentionally disabled.

## Privacy and Network Access

- Conversation transcripts are read from the local machine.
- PrettyTerm does not upload transcript contents to its own server.
- The plan-usage panel requests the authenticated Claude usage endpoint to display the current 5-hour and 7-day limits.
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
build-app.command
```

## Contributing

Bug reports and focused pull requests are welcome. Please include the macOS version, Claude Code version, PrettyTerm version shown in the top-left corner, and exact reproduction steps. Never attach private transcripts, credentials, or session metadata to a public issue.

## License

PrettyTerm is available under the [MIT License](LICENSE).

## Disclaimer

Claude and Claude Code are trademarks of Anthropic. PrettyTerm is an unofficial companion application.
