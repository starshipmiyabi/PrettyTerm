# PrettyTerm Beta 0.8.1 (Build 18)

This beta release applies the first security and performance audit of the 0.8 series.

## Download

Download `PrettyTerm-Beta-0.8.1-build18-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

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
