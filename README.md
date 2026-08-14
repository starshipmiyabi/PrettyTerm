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
- Expandable thinking, tool, error, and line-by-line diff events; per-file diffs start collapsed.
- Codex-style edited-file summaries at the end of each turn, with one-click access to that turn's recorded `Edit` / `Write` review without running Git.
- Inspector for connection state, persistent context usage metering with collapsible `/context` category details, plan limits, estimated API-equivalent cost, changed files, tasks, an expandable native Git review, and explicit Git publishing actions.
- Remembered Git observation directories discovered from the selected Claude Code transcript, plus manually added directories.
- Always-on-top floating conversation window.
- Custom rounded composers shared by the main and floating windows, with text, image, file-picker, and drag-and-drop input.
- In-composer model and reasoning-effort controls that send the exact `/model` and `/effort` commands to the verified Terminal session.
- Custom inline `AskUserQuestion` cards plus a borderless native panel for the independent `ask_via_prettyterm` MCP bridge.
- One-click **Compact** control that sends the exact `/compact` command to the currently verified Terminal conversation.
- Transcript-aware waiting animation that appears after a successful message send and disappears when Claude's first real reply or tool event reaches the local JSONL transcript.
- Warm beige and deep-orange light and dark appearances designed to reduce glare.
- Built-in Simplified Chinese and English interface selection, persisted locally across launches.

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

PrettyTerm watches Claude Code JSONL transcripts under `~/.claude/projects` and renders a read-only conversation snapshot in a local `WKWebView`. Active transcripts are parsed from their last completed byte offset, and newly appended messages are added without replacing the existing conversation DOM. A session handshake prevents metadata-only appends from clearing the conversation if WebKit has reloaded. When the inspector changes width, PrettyTerm preserves a character-level reading anchor so text reflow does not jump the conversation to another passage. Sending remains anchored to Apple Terminal: PrettyTerm validates the selected Claude PID, TTY, exact process name, and session before writing to the bound tab. Every text submission ends with one additional, independently delivered Return after the body, preventing Terminal's body-adjacent Return from being absorbed as paste input. After Terminal accepts a message, a transcript-aware waiting signal remains visible until Claude's first real reply or tool event arrives.

PrettyTerm does not replace Claude Code or run a separate agent service. Claude.ai Remote Control is intentionally disabled.

## Composer and Question Flows

The main and floating composers use the same custom warm controls. Images selected, pasted, or dropped into a composer are sent through Claude Code's image attachment path. Other selected or dropped files are appended as exact, deduplicated `@/absolute/path` references, including paths containing spaces. Model and reasoning-effort changes are sent only to the currently verified Terminal session; changing the visual control never changes a different session.

When Claude Code records an `AskUserQuestion` tool call in the transcript, PrettyTerm renders it as an inline question card with vertical single-choice or multiple-choice options and an optional free-text answer. The matching transcript tool result updates that card in place to a read-only answered state.

The independent `ask_via_prettyterm` MCP bridge uses request and response files under `~/.claude/prettyterm-questions`. PrettyTerm presents each request in a custom borderless native panel with vertically arranged answer controls. It writes only the answers selected or typed by the user; it does not generate an answer automatically.

## Context and Usage Inspector

The context card always keeps the latest total token count, percentage, and progress meter visible. Its optional details are sourced from Claude Code's real `/context` transcript records and start collapsed. When available, PrettyTerm shows System prompt, System tools, Memory files, Skills, Messages, Free space, and Autocompact buffer without estimating missing categories or counting deferred tools as loaded context.

Plan-limit data comes from Claude Code's zero-turn `/usage` command running with a UTC environment. PrettyTerm accepts both exact-hour and minute reset formats, refreshes once per minute, and presents only countdown durations in the selected interface language.

## Terminal Submission Reliability

Visual wrapping inside PrettyTerm's composer is layout-only and never inserts newline characters into the outgoing message. Apple Terminal can deliver a long `do script` payload in several roughly 1,022-byte chunks, with its automatically appended Return arriving beside the final body chunk. Interactive terminal applications may interpret that body-adjacent Return as part of pasted input instead of a submit action.

PrettyTerm therefore completes every text command with one additional Return delivered independently after the body. The Return-only automation uses an empty `do script`, which makes Terminal emit exactly one CR; explicitly supplying CR would make Terminal append another and produce two. The same verified TTY, PID, process-name, and Claude session binding protects both the body and final submit action. This applies to visually wrapped single-line text, true multiline text, model changes, and the Compact command.

## Git Inspector and Directory Scope

The inspector can widen on demand to show the selected repository's local Git status and diff. This explicit Git review reads the current working tree. Separately, a turn containing `Edit` or `Write` events ends with an edited-files summary; clicking **Review** opens the exact before/after content recorded in that turn. Turn review does not run `git diff`, does not require a repository, and is not affected by the selected Git observation directory. Individual transcript diffs remain available inside the conversation and start collapsed. PrettyTerm supports exactly three sources for Git observation directories:

- **Successful `/add-dir`:** PrettyTerm watches the selected conversation's JSONL file and reparses only newly appended records as soon as Claude Code writes its success confirmation. It does not wait for a full projects-directory scan.
- **Manual directories:** Enter or paste an absolute folder path in the inspector to add it directly to PrettyTerm's remembered Git directory list. The path field owns Command-V while focused; the conversation composer cannot intercept it.
- **Directories Claude visits while running:** PrettyTerm passively collects transcript `cwd` values, structured Read/Edit/Write paths, file snapshots, tool-result paths, and absolute path arguments used by Agent Bash commands. File accesses remember their containing folder.

The selected remembered directory can be deleted from the inspector. Deletion creates a persistent local exclusion, so passive transcript discovery will not resurrect it after switching or reopening conversations. Only manually adding that path again clears the exclusion and restores it.

The directory controls only change where PrettyTerm runs Git operations. They do not change Claude Code's working directory, grant Claude Code access to a folder, send terminal input, or execute a Claude Code command. To let Claude Code access another folder, run `/add-dir /absolute/path` inside Claude Code itself. PrettyTerm can then remember transcript directories that Claude Code records while working.

The Git review presents branch and file summaries, old/new line numbers, colored addition and deletion rows, collapsed unchanged ranges, binary-file notices, and status-only entries for untracked files. Raw Git protocol headers are not shown. Expanding, collapsing, refreshing, and replacing review content use motion-aware transitions; macOS Reduce Motion is respected. Large Git output is still truncated locally to keep the interface responsive.

The **Commit or Push** panel offers **Commit**, **Commit and Push**, and **Push**. PrettyTerm never generates a commit message: commit actions stay disabled until the user enters one manually. The optional **Include unstaged changes** checkbox runs `git add -A` for the selected repository before committing; when unchecked, only the existing index is committed. Push never creates a commit. Git is launched directly with argument arrays rather than through a shell. These are explicit write/network operations and can run repository-configured Git hooks.

## Interface Language

Use the language selector in the title bar to choose **中文** or **English**. The preference is saved locally and applies to the native window, conversation chrome, turn review, Git review, menus, and macOS permission descriptions. Switching language rebuilds only the presentation layer: the selected Claude session, unsent draft, pending image attachments, Terminal binding, and remembered Git directories remain intact.

## Privacy and Network Access

- Conversation transcripts are read from the local machine.
- PrettyTerm does not upload transcript contents to its own server. An explicit Git push sends repository commits only to that repository's configured remote.
- PrettyTerm does not read Claude Code credentials or request Keychain authorization. The plan-usage panel runs Claude Code's zero-turn local `/usage` command, so Claude Code owns its existing login and token refresh path; the command reports zero model turns and zero API-equivalent cost.
- The obsolete Accessibility-based input experiment and its permission description have been removed. File and transcript reads use the application's direct, non-sandboxed filesystem access.
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
