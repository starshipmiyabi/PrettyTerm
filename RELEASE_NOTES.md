# PrettyTerm Beta 0.9.8 (Build 38)

PrettyTerm Beta 0.9.8 brings the new home and multi-conversation workflow, large Review and Files workspaces, complete transcript rendering improvements, direct file preview, refreshed app identity, and the accumulated composer, inspector, Terminal, and interaction work from this development cycle.

## Download

Download `PrettyTerm-Beta-0.9.8-build38-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

For this update, remove and re-add PrettyTerm Beta in System Settings → Privacy & Security → Accessibility. Earlier local builds tied keyboard access to an older executable hash; Build 38 uses a stable application identity for subsequent local updates.

## Composer and Attachments

- Replaces the main and floating composers with custom warm, rounded surfaces and motion-aware controls instead of native button chrome.
- Adds file and image selection plus drag-and-drop. Images remain native Claude Code image attachments; other files use exact, deduplicated `<attach>/absolute/path</attach>` markers so sending never stops inside Claude Code's interactive `@` autocomplete.
- Preserves source PNG bytes for selected and dropped images and removes the `NSImage -> TIFF -> PNG` corruption path. Keeps each PNG on the clipboard until Claude completes its asynchronous image read, then advances to the next image and submits the accompanying text.
- Adds custom model and reasoning-effort controls. Model and effort changes use the verified Terminal session and the exact `/model` and `/effort` commands.
- Fixes the effort slider twice at the event-source level: it no longer blocks the AppKit event loop, and its click/drag recognizers now submit exactly once after the gesture ends.

## Questions and Waiting Feedback

- Renders transcript `AskUserQuestion` calls as custom inline single-choice, multiple-choice, and free-text cards, then displays the recorded answer when the matching tool result arrives.
- Adds the independent `ask_via_prettyterm` MCP request bridge with a custom borderless native panel, vertically arranged options, a custom input surface, and smooth selection and submission feedback.
- Removes native traffic-light, button-bezel, and blue focus-ring chrome from the MCP panel.
- Fixes the custom option hit testing so the first click, selection changes, submit control, and close control all receive the intended pointer event.
- Shows the warm Terminal-to-Claude waiting route only after Terminal accepts a message and removes it on the first real assistant or tool event.

## Inspector, Context, and Git

- Keeps context total, percentage, and progress visible while allowing real transcript `/context` categories to expand and collapse. Missing categories are never estimated and opening Details never sends a command.
- Presents plan limits as five-hour and seven-day meters using UTC requests and locale-neutral countdowns.
- Refines the native Git review, preserves the conversation reading anchor while the inspector resizes, and opens turn-local `Edit` / `Write` review without requesting `git diff`.
- Remembers Git observation directories from successful `/add-dir` records, manually entered paths, and directories Claude actually visits, while preserving explicit user deletions.

## Review and File Workspaces

- Moves Git and turn-local change review into a large in-app page that pushes the conversation left and retains a draggable split width.
- Adds a matching Files page with a collapsible project tree rooted at the selected conversation directory, plus explicit folder switching.
- Renders Markdown as formatted content with MathJax and presents source code or plain text in full with line numbers; binary and advanced document formats are omitted from the tree.
- Uses the same 0.22-second ease-in/ease-out motion for Review, Files, file-tree, and inspector layout changes, and preserves their state across interface-language rebuilds.

## Home, Conversations, and Rendering

- Adds a dedicated home page for choosing a project and starting a new Claude Code conversation without replacing the current conversation.
- Adds independent conversation tabs with retained drafts, Terminal bindings, attachments, and close controls.
- Adds persistent conversation renaming and project-group collapse state.
- Groups consecutive tool calls, keeps ordinary assistant output visible, and adds one-click copying for exact Claude output.
- Adds Escape interruption for an active Claude reply and keeps Remote and Compact routed to the selected Terminal conversation.
- Improves incremental rendering, viewport anchoring, large-diff handling, MathJax startup, and memory use for long conversations.
- Makes each edited-file row open the current file directly while the summary header continues to open turn-local review.

## Visual Identity

- Replaces the application icon and in-app identity marks with the new transparent orange PrettyTerm flower.
- Keeps the mark background-free so it remains consistent across light and dark appearances.

## Reliability and Localization

- Preserves drafts and attachments while switching between Simplified Chinese and English.
- Clears both composers only after a successful send and keeps the main and floating attachment states independent.
- Keeps one or more pasted images in Claude's input buffer until the accompanying text is submitted as the same turn.
- Sends Ctrl+V after Terminal becomes active, preserves image-transfer error details, and gives local builds a stable signing identity so keyboard access can survive rebuilding.
- Fully removes the Files workspace before restoring the inspector, preventing competing width constraints from expanding the main interface.
- Uses the WebView session identity to match incremental transcript appends to the loaded conversation.
- Adds a Remote button that sends `/remote-control` through the selected Terminal session.

## Package

Build 38 is distributed as a versioned macOS DMG with a matching SHA-256 checksum file.

---

# PrettyTerm Beta 0.9.1 (Build 27)

This beta turns the inspector into a clearer live status surface, adds transcript-grounded context breakdowns, and gives visible feedback while Claude is preparing a response.

## Download

Download `PrettyTerm-Beta-0.9.1-build27-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Context Usage Details

- Keeps the current context token count, percentage, and warm progress meter visible at all times.
- Adds a Details disclosure that starts collapsed and expands System prompt, System tools, Memory files, Skills, Messages, Free space, and Autocompact buffer rows.
- Passively parses Claude Code's real `/context` records from both ANSI local-command output and its Markdown metadata record; PrettyTerm does not invent category proportions.
- Preserves Claude Code's category order and excludes deferred tools that are not loaded into the active context.

## Waiting Feedback and Rendering Reliability

- Shows a warm animated Terminal-to-Claude signal after Terminal accepts a message, then removes it when the first real assistant reply or tool event reaches the transcript.
- Uses an evenly spaced Claude starburst, dark-mode styling, and a static Reduce Motion presentation.
- Adds an explicit WebView session handshake before metadata-only incremental appends, falling back to a complete snapshot if WebKit has reloaded or lost session state.
- Avoids repeatedly serializing the full conversation during normal incremental updates in both the main and floating windows.

## Inspector and Usage Polish

- Reworks plan limits into separate five-hour and seven-day meters and refreshes them once per minute.
- Runs Claude Code `/usage` with a UTC environment, accepts exact-hour and minute reset formats, and displays only locale-neutral countdown durations in the interface.
- Displays plan-limit data when both five-hour and seven-day fields are available.
- Adds expandable per-model API-equivalent cost rows with token-type detail and a red/green code-change summary.
- Improves native Git review typography, file hierarchy, line markers, changed-line totals, and spacing while retaining the warm beige and deep-orange appearance.

## Validation

The release passed renderer, waiting-state, appearance, transcript-context parsing, context disclosure, viewport anchoring, incremental-render handshake, UTC plan-usage, Git review, AppKit interaction, Terminal-routing, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

---

# PrettyTerm Beta 0.8.8 (Build 26)

This beta adds one-click context compaction and makes Terminal submission resilient when long or visually wrapped text is interpreted as pasted input.

## Download

Download `PrettyTerm-Beta-0.8.8-build26-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Reliable Terminal Submission

- Delivers one additional independent Return after every text command, including single-line, multiline, model-switch, and Compact commands.
- Uses an empty Terminal `do script` for the independent submit action, producing exactly one CR instead of the two CR bytes caused by explicitly supplying carriage return.
- Keeps the extra submit signal separate from visual text wrapping; AppKit wrapping never mutates the underlying message string.
- Adds regression coverage for the exact single-Return automation path and for every command remaining on the verified Terminal bridge.

## Compact Command

- Adds a **Compact** button to the selected conversation toolbar.
- Sends the exact `/compact` command only after the current Claude Code conversation has been verified and bound to its Terminal TTY and process.
- Sends through the selected conversation's Terminal route.

## Validation

The release passed raw Terminal byte-transport probes, renderer, appearance, Terminal-routing, text submission, Compact command, transcript-increment, Git review, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

---

# PrettyTerm Beta 0.8.7 (Build 25)

This hotfix repairs Claude Code `/add-dir` discovery and inspector path pasting, and removes PrettyTerm-originated credential and Accessibility authorization prompts.

## Download

Download `PrettyTerm-Beta-0.8.7-build25-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Directory Discovery and Pasting

- Watches the selected conversation's JSONL file and incrementally parses that file immediately when Claude Code 2.1.226 writes its ANSI-colored `<local-command-stdout>Added … as a working directory…</local-command-stdout>` success record; `/add-dir` no longer waits for a full projects-directory scan.
- Limits remembered-directory input to three sources: successful `/add-dir`, manual entry, and directories Claude passively records while running through session `cwd`, Read/Edit/Write and tool-result paths, file-history snapshots, or Agent Bash absolute arguments.
- Keeps discovery passive and stores user deletions as persistent exclusions; switching or reopening a conversation cannot resurrect a removed directory, while manual re-entry explicitly restores it.
- Prevents the conversation composer from intercepting Command-V while the inspector path field owns keyboard focus.
- Adds native parser and AppKit focus-chain regressions covering the exact failures.

## Direct Access Without Extra Authorization Prompts

- Removes PrettyTerm's direct Keychain credential read and the obsolete Accessibility-based input experiment, including its usage-description key and linked frameworks.
- Reads local transcripts and directories directly as a non-sandboxed application.
- Delegates plan usage to Claude Code's own zero-turn `/usage` command, which returned `num_turns: 0` and `total_cost_usd: 0` during validation.

## Validation

The release passed ANSI `/add-dir` parsing, focused path-paste routing, zero-turn plan-usage parsing, renderer, appearance, Terminal-routing, transcript-increment, Git review, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, and strict code-signature checks.

---

# PrettyTerm Beta 0.8.6 (Build 24)

This beta completes the review workflow with a warm eye-comfort palette, transcript-accurate per-turn edit review, stable resizing, explicit commit and push controls, and selectable Chinese or English UI.

## Download

Download `PrettyTerm-Beta-0.8.6-build24-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Warm Review Appearance

- Replaces the cool gray/blue chrome with a warm beige canvas and restrained deep-orange accents.
- Applies matching dynamic light/dark colors to native surfaces, the conversation renderer, and the structured Git review.
- Keeps additions and deletions distinct without returning to a high-glare terminal palette.

## Turn-Level Edit Review

- Adds one edited-files summary at the end of every conversation turn containing `Edit` or `Write` events.
- Aggregates file count and addition/deletion totals, shows the first files, and folds longer lists.
- Opens the exact `Edit` / `Write` before-and-after content recorded in that turn, including from the floating conversation.
- Does not request `git diff`, require a repository, or depend on the selected Git observation directory; explicit inspector Git review remains a separate current-worktree action.
- Keeps individual conversation diffs available but collapsed by default.

## Stable Inspector Resizing

- Preserves the currently read character position while inspector resizing reflows conversation text.
- Keeps bottom-following behavior when the reader is already at the newest message, while a scrolled historical position remains visually anchored.

## Chinese and English Interface

- Adds a title-bar selector for Simplified Chinese and English and persists the choice locally.
- Localizes native controls, menus, conversation chrome, turn review, Git review, and macOS permission descriptions.
- Rebuilds only the presentation layer when switching languages, preserving the selected session, Terminal binding, unsent draft, pending images, and remembered Git directories.

## Explicit Commit and Push

- Adds Commit, Commit and Push, and Push actions for the selected repository.
- Requires a manually typed commit message before either commit action becomes available; no message is generated automatically.
- Offers an explicit Include unstaged changes option before commit, while Push never creates a commit.
- Runs Git with argument arrays instead of shell interpolation and reports Git failures in the action panel.
- Keeps the Claude Code directory boundary unchanged: PrettyTerm's selector does not grant access, and `/add-dir` still belongs in Claude Code.

## Validation

The release passed renderer, warm-appearance, edited-turn summary, structured Git-review, Git publishing, directory-memory, Terminal-routing, transcript-increment, usage, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

## Known Limitations

- Requires macOS 13 or later and Apple Terminal.
- This beta is not notarized. The current build uses ad-hoc signing because no Apple Developer ID identity is available in the build environment.
- Terminal automation permission may need to be granted again after an update.

---

# PrettyTerm Beta 0.8.4 (Build 22)

This beta replaces the inspector's terminal-style Git dump with a native review experience and includes the directory-memory controls developed during the local 0.8.3 preview.

## Native Git Review

- Replaces raw Git status and unified-diff protocol output with a structured AppKit review document.
- Groups changes by file and shows branch/upstream context plus per-file and aggregate addition/deletion totals.
- Adds old/new line-number columns, green and red line backgrounds, collapsed unchanged-range summaries, binary-file notices, and untracked-file entries.
- Keeps raw file markers, object indexes, and hunk headers out of the user-facing inspector.

---

# PrettyTerm Beta 0.8.3 (Build 20)

This beta hotfix restores message delivery and adds a small session-navigation improvement. Build 19 was never distributed: it fixed AppleScript error `-2740` but a second compiler error (`-1700`) in the same code path still blocked every send. Build 20 fixes both and adds regression coverage that compiles all three Terminal automation actions.

## Download

Download `PrettyTerm-Beta-0.8.3-build20-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Critical Fix

- Fixes AppleScript error `-2740` that prevented every text, multiline Return, and image-paste action from reaching Terminal. The PID revalidation shell command is now wrapped in syntax accepted by the macOS AppleScript compiler.
- Fixes a second AppleScript error (`-1700`): the process list returned by `processes of theTab` must be assigned to a local variable before its items can be coerced to text, or the coercion fails at runtime.
- Adds compile-time regression coverage for all three Terminal automation actions (text, Return, image paste), including text containing quotes, backslashes, and line breaks, so a script that merely *looks* correct can no longer ship without actually compiling.

## Session Navigation

- Adds a session-table context menu for revealing the selected transcript in Finder or copying its absolute path without switching the active conversation.

## Terminal and Runtime

- Strips ESC, C0, and C1 terminal control characters from composer text before constructing a Terminal submission, preventing bracketed-paste frame escape.
- Revalidates the exact Claude PID and TTY inside the Terminal AppleScript and requires the exact `claude` process name instead of a substring match.
- Reads Claude Code credentials with `SecItemCopyMatching`, binding Keychain authorization to PrettyTerm rather than `/usr/bin/security`.
- Renders Markdown links directly and leaves bundled MathJax extensions available.
- Enables Hardened Runtime and the Apple Events entitlement for every build. Developer ID builds also receive a secure timestamp.

## Performance and Reliability

- Uses scalable exact differences for full Git output and transcript edit rows.
- Parses only appended bytes for active JSONL transcripts; forced refreshes and rewritten files are parsed from their current contents.
- Appends new conversation nodes in both windows instead of replacing the full DOM, preserving expanded details, text selection, and historical scroll state.
- Replaces the source-text hash with behavioral tests for PID, TTY, exact process name, and target-mismatch handling.
- Adds a reproducible DMG packaging command with a versioned artifact and SHA-256 checksum.

## Routing and Privacy

- Claude.ai Remote Control is available from the conversation toolbar.
- PrettyTerm's Git directory selector never changes Claude Code's working directory; the interface directs users to run `/add-dir` inside Claude Code when access is required.
- Transcript content is read locally from Claude Code JSONL files.
- Terminal writes use the selected Claude PID, TTY, exact process name, and session identity.

## Validation

The release passed renderer, appearance, Terminal-routing, transcript-increment, usage, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

## Known Limitations

- Requires macOS 13 or later and Apple Terminal.
- This beta is not notarized. Local builds use ad-hoc signing unless a Developer ID Application identity is supplied.
- Terminal automation permission may need to be granted again after an update.
