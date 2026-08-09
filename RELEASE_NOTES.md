# PrettyTerm Beta 0.8.0 (Build 17)

This beta release focuses on reliability, session safety, and a more useful native workspace around Claude Code in Apple Terminal.

## Download

Download `PrettyTerm-Beta-0.8.0-build17-macOS.dmg`, open it, and drag PrettyTerm to the Applications shortcut. `SHA256SUMS.txt` is provided for integrity verification.

## Highlights

- Added a visible runtime version label for easier bug reporting.
- Added live 5-hour and 7-day Claude plan-usage indicators.
- Added per-session API-equivalent cost estimates.
- Added an inspector for connection state, context, changed files, and tasks.
- Added an expandable Git diff view that widens the inspector on demand.
- Added remembered Git observation directories from Claude Code transcripts and manual path entry.
- Git observation remains read-only and local: changing the PrettyTerm directory never changes or extends Claude Code's directory access.
- Added an independent always-on-top floating conversation window.
- Improved Markdown, LaTeX, table, code, and diff rendering.

## Reliability Fixes

- Ordered lists now keep their sequence across indented continuation paragraphs.
- Inspector dividers retain the width selected by dragging instead of snapping back during Auto Layout.
- Thin split-view dividers now expose a larger invisible drag target.
- Changed-file buttons preserve identity across transcript refreshes and remain clickable after window movement or resizing.
- Sending remains bound to the validated Terminal TTY and Claude session.
- Failed sends preserve the composer text.
- Successful sends now clear both composers through the native text-editing transaction, including Enter-triggered submissions.

## Safety and Privacy

- Claude.ai Remote Control remains disabled.
- PrettyTerm's Git directory selector never changes Claude Code's working directory; the interface directs users to run `/add-dir` inside Claude Code when access is required.
- Transcript content is read locally from Claude Code JSONL files.
- Terminal writes are rejected when the selected Claude process cannot be validated.

## Validation

The release passed the JavaScript renderer and appearance suites, native session and usage tests, AppKit interaction regression tests, application build checks, bundle-resource comparisons, property-list validation, and strict code-signature verification.

## Known Limitations

- Requires macOS 13 or later and Apple Terminal.
- This beta is not notarized and may use ad-hoc signing.
- Terminal automation permission may need to be granted again after an update.
