# PrettyTerm Beta

PrettyTerm is a lightweight native macOS interface for Claude Code. It runs Claude Code in the background, sends text and images together, streams responses into a focused conversation interface, and reads local transcripts to preserve conversation history.

Current release: **0.9.9 (Build 7)** — [download the macOS beta](https://github.com/starshipmiyabi/PrettyTerm/releases/tag/v0.9.9-beta.7).

> [!IMPORTANT]
> PrettyTerm is beta software. It is an independent community project and is not affiliated with or endorsed by Anthropic.

## Highlights

- Native AppKit interface with no full Xcode project required.
- Dedicated home page for choosing a project and starting a new Claude Code conversation.
- Independent conversation tabs that retain their own draft, attachments, and Claude session.
- Local session discovery from `~/.claude/projects`.
- Managed background Claude Code sessions with structured image-and-text input and live streaming output.
- Markdown rendering for headings, lists, quotes, links, syntax-highlighted code blocks with one-click copying, and tables.
- Bundled MathJax rendering for inline and display LaTeX.
- Expandable thinking, tool, error, and line-by-line diff events; per-file diffs start collapsed.
- Grouped tool activity, exact Claude-output copying, and a Stop button available throughout Claude's work.
- Codex-style edited-file summaries at the end of each turn, with one-click access to that turn's recorded `Edit` / `Write` review without running Git.
- Large in-app Review and Files pages that push the conversation aside, retain draggable split widths, and transition with one consistent motion curve.
- Project file browsing for Markdown, source code, plain text, images, and Jupyter notebooks; Markdown opens as rendered content with MathJax, source files keep complete text and line numbers, and notebook cells show their outputs.
- Persistent conversation renaming and project-group collapse state.
- Inspector for connection state, persistent context usage metering with collapsible `/context` category details, plan limits, estimated API-equivalent cost, changed files, tasks, an expandable native Git review, and explicit Git publishing actions.
- Remembered Git observation directories discovered from the selected Claude Code transcript, plus manually added directories.
- Always-on-top floating conversation window.
- Custom rounded composers shared by the main and floating windows, with text, image, file-picker, and drag-and-drop input.
- In-composer model, reasoning-effort, and permission-mode controls connected directly to the background Claude session, with confirmed settings saved to Claude Code's configuration.
- Searchable slash-command suggestions with icons, descriptions, keyboard navigation, and live matching as the user types.
- Custom inline `AskUserQuestion` cards plus a borderless native panel for the independent `ask_via_prettyterm` MCP bridge.
- One-click **Compact** with compaction status and token counts supplied by Claude Code.
- Live text, thinking, and tool output that merges into persisted history, plus a circular jump-to-bottom button when reading earlier messages.
- Warm beige and deep-orange light and dark appearances designed to reduce glare.
- Transparent orange PrettyTerm flower identity shared by the app icon, title bar, and home page.
- Built-in Simplified Chinese and English interface selection, persisted locally across launches.

## Requirements

- macOS 13 Ventura or later.
- Claude Code installed and signed in, with support for streaming JSON and session control requests. The current integration was developed against Claude Code 2.1.275.
- Claude Code available as `claude` in the user's login shell. Terminal does not need to remain open.

Building from source additionally requires the macOS Command Line Tools. Running the JavaScript tests separately requires Node.js.

## Install a Release

1. Download the latest `PrettyTerm-Beta-*.dmg` from [Releases](https://github.com/starshipmiyabi/PrettyTerm/releases).
2. Open the disk image and drag `PrettyTerm Beta.app` to the **Applications** shortcut.
3. Ensure Claude Code is installed and signed in.
4. Open PrettyTerm and select an existing conversation, or choose a project on the home page to start one. Claude connects in the background.

When updating, replace the application and quit and reopen PrettyTerm to load the new build.

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

PrettyTerm watches Claude Code JSONL transcripts under `~/.claude/projects` and renders the conversation in a local `WKWebView`. Conversations open in any tab or the floating window keep their complete transcript loaded; unopened conversations retain lightweight summaries for the sidebar. Active transcripts are parsed from their last completed byte offset, and newly appended messages are added without replacing the existing conversation DOM. A session handshake matches metadata-only appends to the loaded conversation. When the inspector changes width, PrettyTerm preserves a character-level reading anchor so text reflow stays at the same passage. Sending uses a managed Claude Code process over streaming JSON. The same process receives image and text blocks and emits live response events; selecting a conversation connects its background session without opening Terminal.

PrettyTerm uses the installed Claude Code executable for requests, tools, authentication, and session persistence. The Remote button enables Remote Control through the selected background session's control protocol.

## Composer and Question Flows

The main and floating composers use the same custom warm controls. Images selected, pasted, or dropped into a composer remain attached until Send is pressed. All images and the accompanying text are then submitted as one structured user message. Original PNG bytes are preserved, and converted formats bypass the lossy `NSImage -> TIFF` round trip. Sent images also appear in conversation history as expandable thumbnails. Other selected or dropped files are appended as exact, deduplicated `<attach>/absolute/path</attach>` markers, including paths containing spaces, without opening Claude Code's interactive `@` autocomplete. Model changes use Claude Code's set_model control request. The selected session connects automatically, and the acknowledged model remains displayed when older transcript records refresh. Reasoning-effort changes are sent to the same background session.

When Claude Code records an `AskUserQuestion` tool call in the transcript, PrettyTerm renders it as an inline question card with vertical single-choice or multiple-choice options and an optional free-text answer. Answers to active protocol questions are returned on the same Claude connection. The matching live or transcript tool result updates that card in place with the recorded answer, instead of leaving a separate tool-result card at the bottom.

The independent `ask_via_prettyterm` MCP bridge uses request and response files under `~/.claude/prettyterm-questions`. PrettyTerm presents each request in a custom borderless native panel with vertically arranged answer controls. It writes only the answers selected or typed by the user; it does not generate an answer automatically.

## Context and Usage Inspector

The context card always keeps the latest total token count, percentage, and progress meter visible. Its optional details are sourced from Claude Code's real `/context` transcript records and start collapsed. When available, PrettyTerm shows System prompt, System tools, Memory files, Skills, Messages, Free space, and Autocompact buffer without estimating missing categories or counting deferred tools as loaded context.

Plan-limit data comes from Claude Code's structured `get_usage` control request with `skip_behaviors`, at connection, after completed turns and once per minute. Native `rate_limit_event` updates also refresh the meter during responses. This path uses no model turn and needs no Terminal status-line file. Reset times arrive as timestamps and are displayed as countdowns.

## Managed Claude Session Input

PrettyTerm manages a background Claude Code process using streaming JSON over stdin/stdout. Each send contains all image blocks and the text in one user message. Claude accepts that message directly; sending no longer depends on Terminal clipboard operations, image-cache files, or a simulated Return.

Partial output is enabled on the same connection. Text, thinking blocks and tool inputs update in place as events arrive, in both the main conversation and its floating view. Completed blocks adopt their transcript identifiers and merge into persisted history without being displayed twice. History remains file-backed; live output does not wait for transcript polling or require a Terminal window.

Connecting an existing conversation ends its matching interactive Claude process and resumes the same session ID in the background. Shell configuration, Claude authentication and project settings remain owned by Claude Code. The input is cleared after Claude echoes the submitted message UUID. The Stop button remains available while Claude is working, including tool activity, and sends the protocol's interrupt request. Working state clears when the corresponding work completes. Model changes and Remote Control use their corresponding control requests.

Requests, authentication, tools and prompt-cache markers remain owned by Claude Code. PrettyTerm resumes the same session ID and keeps the process running between sends. Model changes use Claude Code's normal cache behavior: switching models builds that model's cache; unchanged prefixes can be reused while still within their cache lifetime.

## Commands without Terminal

Typing `/` opens an in-window command palette with icons and descriptions. Further typing matches command names, localized titles, and descriptions; arrow keys select an item, Return or Tab inserts it, and Escape closes the palette. Selecting a suggestion fills the composer without sending it. The command list comes from the running Claude Code process. Built-ins, project commands, skills and plugins use that process and its command lifecycle; `commands_changed` refreshes the palette when Claude discovers more commands. `/commands` and `/help` open the palette as well. Commands that require a terminal UI are not advertised by Claude Code in this mode.

`/config`, `/model`, `/effort` and `/mode` open PrettyTerm controls. Model and effort arguments use session control requests. Mode choices include Plan, Auto, Bypass, Default and Accept edits, using Claude Code's `set_permission_mode` protocol. After a control request succeeds, PrettyTerm reads the effective session settings and saves the confirmed choice to `~/.claude/settings.json`; the saved permission mode is also used when the background session starts again. Configuration requests and responses are recorded in `~/Library/Logs/PrettyTerm/configuration.jsonl`. The model picker includes Sonnet 4.6 and Opus 5.5. Native tool requests and questions are answered in PrettyTerm and sent back on that connection.

`/compact [instructions]` and the Compact button run Claude Code's compaction on the existing conversation. The UI displays its compacting status, completion or error, and before/after token counts when returned. Synthetic configuration acknowledgements do not enter the live conversation history. Command output appears in the status area and can be opened from **Advanced → View command result** or the `/` menu.

## Git Inspector and Directory Scope

The inspector can widen on demand to show the selected repository's local Git status and diff. This explicit Git review reads the current working tree. Separately, a turn containing `Edit` or `Write` events ends with an edited-files summary; clicking **Review** opens the exact before/after content recorded in that turn. Turn review does not run `git diff`, does not require a repository, and is not affected by the selected Git observation directory. Individual transcript diffs remain available inside the conversation and start collapsed. PrettyTerm supports exactly three sources for Git observation directories:

- **Successful `/add-dir`:** PrettyTerm watches the selected conversation's JSONL file and reparses only newly appended records as soon as Claude Code writes its success confirmation. It does not wait for a full projects-directory scan.
- **Manual directories:** Enter or paste an absolute folder path in the inspector to add it directly to PrettyTerm's remembered Git directory list. The path field owns Command-V while focused; the conversation composer cannot intercept it.
- **Directories Claude visits while running:** PrettyTerm passively collects transcript `cwd` values, structured Read/Edit/Write paths, file snapshots, tool-result paths, and absolute path arguments used by Agent Bash commands. File accesses remember their containing folder.

The selected remembered directory can be deleted from the inspector. Deletion creates a persistent local exclusion, so passive transcript discovery will not resurrect it after switching or reopening conversations. Only manually adding that path again clears the exclusion and restores it.

The directory controls only change where PrettyTerm runs Git operations. They do not change Claude Code's working directory, grant Claude Code access to a folder, send terminal input, or execute a Claude Code command. To let Claude Code access another folder, run `/add-dir /absolute/path` inside Claude Code itself. PrettyTerm can then remember transcript directories that Claude Code records while working.

The Git review presents branch and file summaries, old/new line numbers, colored addition and deletion rows, collapsed unchanged ranges, binary-file notices, and status-only entries for untracked files. Raw Git protocol headers are not shown. Expanding, collapsing, refreshing, and replacing review content use motion-aware transitions; macOS Reduce Motion is respected. Git output and transcript edit rows are rendered in full.

The **Commit or Push** panel offers **Commit**, **Commit and Push**, and **Push**. A nonempty commit message is passed directly to `git commit -m`. The optional **Include unstaged changes** checkbox runs `git add -A` for the selected repository before committing; when unchecked, only the existing index is committed. **Push** sends existing commits. Git is launched directly with argument arrays rather than through a shell and can run repository-configured Git hooks.

## Interface Language

Use the language selector in the title bar to choose **中文** or **English**. The preference is saved locally and applies to the native window, conversation chrome, turn review, Git review, menus, and macOS permission descriptions. Switching language rebuilds only the presentation layer: the selected Claude session, unsent draft, pending image attachments, Claude connection, remembered Git directories, open Review/Files pages, selected preview file, and panel widths remain intact.

## Privacy and Network Access

- Conversation transcripts are read from the local machine.
- PrettyTerm does not upload transcript contents to its own server. An explicit Git push sends repository commits only to that repository's configured remote.
- PrettyTerm does not read Claude Code credentials or request Keychain authorization. Claude Code owns login and token refresh; the plan-usage panel uses its `get_usage` control request without creating a model turn.
- The obsolete Accessibility-based input experiment and its permission description have been removed. File and transcript reads use the application's direct, non-sandboxed filesystem access.
- The conversation WebView renders Markdown links directly and leaves bundled MathJax extensions available.
- API-equivalent cost is an estimate based on transcript usage data and public API pricing; it is not a subscription charge.

## Current Limitations

- Sending uses a PrettyTerm-managed Claude Code process. Reconnect an existing conversation to transfer it from its interactive terminal process.
- Available slash commands depend on the installed Claude Code version and its headless command list. Terminal-only interactive commands are not included in that list.
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
