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

The release passed renderer, warm-appearance, edited-turn summary, structured Git-review, manual-commit gating, directory-memory, Terminal-safety, transcript-increment, usage, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

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

This beta hotfix restores message delivery after the Terminal safety audit and adds a small session-navigation improvement. Build 19 was never distributed: it fixed AppleScript error `-2740` but a second compiler error (`-1700`) in the same code path still blocked every send. Build 20 fixes both and adds regression coverage that compiles all three Terminal automation actions, closing the gap that let both errors ship unnoticed.

## Download

Download `PrettyTerm-Beta-0.8.3-build20-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Critical Fix

- Fixes AppleScript error `-2740` that prevented every text, multiline Return, and image-paste action from reaching Terminal. The PID revalidation shell command is now wrapped in syntax accepted by the macOS AppleScript compiler.
- Fixes a second AppleScript error (`-1700`) in the same safety check: the process list returned by `processes of theTab` must be assigned to a local variable before its items can be coerced to text, or the coercion fails at runtime.
- Adds compile-time regression coverage for all three Terminal automation actions (text, Return, image paste), including text containing quotes, backslashes, and line breaks, so a script that merely *looks* correct can no longer ship without actually compiling.

## Session Navigation

- Adds a session-table context menu for revealing the selected transcript in Finder or copying its absolute path without switching the active conversation.

## Security Fixes

- Strips ESC, C0, and C1 terminal control characters from composer text before constructing a Terminal submission, preventing bracketed-paste frame escape.
- Revalidates the exact Claude PID and TTY inside the Terminal AppleScript and requires the exact `claude` process name instead of a substring match.
- Reads Claude Code credentials with `SecItemCopyMatching`, binding Keychain authorization to PrettyTerm rather than `/usr/bin/security`.
- Adds a restrictive Content Security Policy and disables MathJax `require` and `autoload` packages.
- Enables Hardened Runtime and the Apple Events entitlement for every build. Developer ID builds also receive a secure timestamp.

## Performance and Reliability

- Moves the large-diff guard before the LCS table allocation, preventing multi-gigabyte WebView allocations.
- Parses only appended bytes for active JSONL transcripts while retaining full-reparse recovery for forced refreshes and rewritten files.
- Appends new conversation nodes in both windows instead of replacing the full DOM, preserving expanded details, text selection, and historical scroll state.
- Replaces the brittle source-text safety hash with behavioral tests for PID, TTY, exact process-name, and unsafe-return requirements.
- Adds a reproducible DMG packaging command with a versioned artifact and SHA-256 checksum.

## Safety and Privacy

- Claude.ai Remote Control remains disabled.
- PrettyTerm's Git directory selector never changes Claude Code's working directory; the interface directs users to run `/add-dir` inside Claude Code when access is required.
- Transcript content is read locally from Claude Code JSONL files.
- Terminal writes are rejected when the selected Claude PID, TTY, exact process name, or session cannot be validated.

## Validation

The release passed renderer, appearance, Terminal-safety, transcript-increment, usage, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

## Known Limitations

- Requires macOS 13 or later and Apple Terminal.
- This beta is not notarized. Local builds use ad-hoc signing unless a Developer ID Application identity is supplied.
- Terminal automation permission may need to be granted again after an update.
