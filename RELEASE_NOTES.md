# PrettyTerm Beta 0.8.4 (Build 22)

This beta replaces the inspector's terminal-style Git dump with a native review experience and includes the directory-memory controls developed during the local 0.8.3 preview.

## Download

Download PrettyTerm-Beta-0.8.4-build22-macOS.dmg, open it, and drag PrettyTerm to the Applications shortcut. SHA256SUMS.txt is provided for integrity verification.

## Native Git Review

- Replaces raw Git status and unified-diff protocol output with a structured AppKit review document.
- Groups changes by file and shows branch/upstream context plus per-file and aggregate addition/deletion totals.
- Adds old/new line-number columns, green and red line backgrounds, collapsed unchanged-range summaries, binary-file notices, and untracked-file entries.
- Keeps raw file markers, object indexes, and hunk headers out of the user-facing inspector.

## Motion and Interaction

- Adds a motion-aware fade when the review expands and contracts.
- Adds a compact activity indicator during Git refresh.
- Cross-fades refreshed review content instead of abruptly replacing the document.
- Respects the macOS Reduce Motion accessibility setting.

## Git Directory Memory

- Adds a delete control for removing the selected Git observation directory from PrettyTerm's saved directory list.
- Keeps a deleted directory hidden during polling of the currently open conversation, preventing immediate accidental rediscovery.
- Allows restoration either by manually adding the directory again or by reopening a conversation whose transcript records it.
- Deletion still affects only PrettyTerm's read-only Git observation scope and never changes Claude Code's working directory or permissions.

## Validation

The release passed renderer, appearance, structured Git-review, directory-memory, Terminal-safety, transcript-increment, usage, AppKit interaction, application build, bundle-resource, property-list, Hardened Runtime, entitlement, DMG, checksum, and strict code-signature checks.

## Known Limitations

- Requires macOS 13 or later and Apple Terminal.
- This beta is not notarized. The published DMG uses ad-hoc signing because no Apple Developer ID identity is available in the build environment.
- Terminal automation permission may need to be granted again after an update.

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
