'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.resolve(__dirname, '../Sources/PrettyTerm.m'),
  'utf8'
);
const agentSource = fs.readFileSync(
  path.resolve(__dirname, '../Sources/PTAgentState.m'),
  'utf8'
);

test('Command-O toggles one independent always-on-top conversation panel', () => {
  assert.match(source, /keyEquivalent:@"o"/);
  assert.match(source, /PTFloatingConversationActionForState/);
  assert.match(source, /NSFloatingWindowLevel/);
  assert.match(source, /NSWindowCollectionBehaviorCanJoinAllSpaces/);
  assert.match(source, /NSWindowStyleMaskNonactivatingPanel/);
});

test('the floating conversation uses the shared message path and closes cleanly', () => {
  const buildMethod = source.match(
    /- \(void\)buildFloatingPanelIfNeeded[\s\S]*?(?=\n- \([^\n]+\))/
  );
  assert.ok(buildMethod, 'floating panel builder must exist');
  assert.match(buildMethod[0], /PTComposerTextView/);
  assert.match(buildMethod[0], /sendFloatingMessage:/);
  assert.match(buildMethod[0], /imagePasteHandler/);
  assert.match(buildMethod[0], /chooseFloatingImages:/);
  assert.match(source, /sendOutgoingMessage:[\s\S]*forSessionID:/);
  assert.match(source, /_bridge\.sessionID isEqual:sessionID/);
  assert.match(source, /sendFloatingMessage:[\s\S]*floatingPendingImagesForClaude/);
  assert.match(source, /windowWillClose:[\s\S]*_floatingSessionID\s*=\s*nil/);
});

test('successful sends clear both composers through the native text editing transaction', () => {
  const mainSend = source.match(
    /- \(void\)sendMessage:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const floatingSend = source.match(
    /- \(void\)sendFloatingMessage:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(source, /clearAfterSuccessfulSubmissionMatchingText:/);
  assert.match(source, /shouldChangeTextInRange:wholeRange replacementString:@""/);
  assert.match(source, /replaceCharactersInRange:wholeRange withString:@""/);
  assert.match(mainSend, /clearAfterSuccessfulSubmissionMatchingText:message/);
  assert.match(floatingSend, /clearAfterSuccessfulSubmissionMatchingText:message/);
  assert.doesNotMatch(mainSend, /_composerTextView\.string\s*=\s*@""/);
  assert.doesNotMatch(floatingSend, /_floatingComposerTextView\.string\s*=\s*@""/);
});

test('both windows append new JSONL messages and retain full-snapshot recovery', () => {
  const mainRender = source.match(
    /- \(void\)renderSession:\(PTSessionInfo \*\)session[\s\S]*?(?=\n- \([^\n]+\))/
  );
  const floatingRender = source.match(
    /- \(void\)renderFloatingSession:\(PTSessionInfo \*\)session[\s\S]*?(?=\n- \([^\n]+\))/
  );
  assert.ok(mainRender, 'main renderer must exist');
  assert.ok(floatingRender, 'floating renderer must exist');
  assert.match(mainRender[0], /window\.setClaudeSession/);
  assert.match(mainRender[0], /window\.appendClaudeMessages/);
  assert.match(floatingRender[0], /window\.setClaudeSession/);
  assert.match(floatingRender[0], /window\.appendClaudeMessages/);
  assert.match(mainRender[0], /PTSessionInfo \*latest = self->_selectedSession/);
  assert.match(floatingRender[0], /sessionWithID:self->_floatingSessionID/);
});

test('clicking sync reparses the selected JSONL and forces both snapshots to redraw', () => {
  const connectMethod = source.match(
    /- \(void\)connectSelectedSession:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  );
  const applyMethod = source.match(
    /- \(void\)applySessions:\(NSArray<PTSessionInfo \*> \*\)sessions[\s\S]*?(?=\n- \([^\n]+\))/
  );
  assert.ok(connectMethod, 'sync button action must exist');
  assert.ok(applyMethod, 'session snapshot application must exist');
  assert.match(connectMethod[0], /refreshForcingPath:_selectedSession\.filePath/);
  assert.match(applyMethod[0], /_manualRefreshSessionID/);
  assert.match(applyMethod[0], /_renderedSessionID\s*=\s*nil/);
  assert.match(applyMethod[0], /_floatingRenderedSessionID\s*=\s*nil/);
});

test('quote bridge is installed for both webviews and routes by webview plus session', () => {
  const registrations = source.match(/addScriptMessageHandler:self name:@"quoteSelection"/g) || [];
  assert.equal(registrations.length, 2);
  assert.match(source, /WKScriptMessageHandler/);
  assert.match(source, /didReceiveScriptMessage/);
  assert.match(source, /message\.webView\s*==\s*_conversationView/);
  assert.match(source, /message\.webView\s*==\s*_floatingConversationView/);
  assert.match(source, /_selectedSession\.sessionID/);
  assert.match(source, /_floatingSessionID/);
  assert.match(source, /_bridge\.sessionID/);
  assert.match(source, /@"> Attached context:\\n%@\\n\\n"/);
  assert.match(source, /insertText:[\s\S]*replacementRange:/);
});

test('both composers are taller and keep slightly wider side margins', () => {
  assert.match(source, /_composerHeightConstraint\s*=\s*\[composerBar\.heightAnchor constraintEqualToConstant:116\]/);
  assert.match(source, /_floatingComposerHeightConstraint\s*=\s*\[composerBar\.heightAnchor constraintEqualToConstant:110\]/);
  assert.match(source, /_composerHeightConstraint\.constant\s*=\s*hasImages\s*\?\s*160\s*:\s*116/);
  assert.match(source, /_floatingComposerHeightConstraint\.constant\s*=\s*hasImages\s*\?\s*158\s*:\s*110/);
});

test('production sending keeps both single-line and multiline messages on the safe Terminal channel', () => {
  const sendMethod = source.match(/- \(BOOL\)sendMessage:\(NSString \*\)message \{[\s\S]*?\n\}/)?.[0] || '';
  assert.match(sendMethod, /\? \[self sendMultilineMessage:message\]/);
  assert.match(sendMethod, /: \[self sendToTerminal:PTNormalizedTerminalPasteText\(message\)\]/);
  assert.doesNotMatch(sendMethod, /pasteAndSubmitMultilineMessage/);
  assert.doesNotMatch(sendMethod, /AXIsProcessTrusted/);
  assert.match(source, /markerAfter >= 0 && markerAfter != markerBefore/);
  assert.match(agentSource, /do script \(ASCII character 13\) in theTab/);
  assert.match(agentSource, /if processName is \\\"claude\\\" then set isSafe to true/);
  assert.doesNotMatch(agentSource, /contains \\\"laude\\\"/);
  assert.doesNotMatch(agentSource, /do script \\\"\\\" in theTab/);
});

test('Claude.ai Remote Control is hard-disabled', () => {
  assert.doesNotMatch(source, /sendToTerminal:@"\/remote-control/);
  assert.match(source, /_remoteButton\.enabled = NO/);
  assert.match(source, /buttonWithTitle:@"RC 已禁用" target:nil action:nil/);
});

test('the top-left app identity shows the running bundle version and build', () => {
  assert.match(source, /bundleInfo\[@"CFBundleShortVersionString"\]/);
  assert.match(source, /bundleInfo\[@"CFBundleVersion"\]/);
  assert.match(source, /visibleAppVersion = \[NSString stringWithFormat:@"%@ · v%@ \(%@\)"/);
  assert.match(source, /\[self label:visibleAppVersion size:17/);
});

test('changed-file buttons accept the first click after Finder deactivates the app', () => {
  assert.match(source, /@interface PTFirstMouseButton : NSButton/);
  assert.match(source, /acceptsFirstMouse:[\s\S]*return YES/);
  assert.match(source, /PTFirstMouseButton \*button/);
  assert.match(source, /action = @selector\(revealChangedFile:\)/);
});

test('Git diff observes remembered transcript directories without changing Claude Code cwd', () => {
  assert.match(source, /NSMutableOrderedSet<NSString \*> \*accessedDirectories/);
  assert.match(source, /session\.accessedDirectories = accessedDirectories\.array/);
  assert.match(source, /PTGitObservedDirectories/);
  assert.match(source, /PTRunGit\(directory, @\[@"diff", @"--no-ext-diff", @"--no-color", @"HEAD"/);
  assert.match(source, /展开 Git diff →/);
  assert.match(source, /不会改变 Claude Code/);
  assert.match(source, /Claude Code 执行 \/add-dir/);
});

test('active transcripts parse only appended JSONL bytes', () => {
  assert.match(source, /PTReadFileDataFromOffset/);
  assert.match(source, /previousParsedSize/);
  assert.match(source, /PTParseSessionAppending/);
  assert.match(source, /@"parsedSize"/);
});

test('Claude credentials are read by PrettyTerm instead of the security CLI', () => {
  assert.match(source, /SecItemCopyMatching/);
  assert.match(source, /kSecAttrService:\s*@"Claude Code-credentials"/);
  assert.doesNotMatch(source, /find-generic-password/);
  assert.doesNotMatch(source, /PTRunTool\(@"\/usr\/bin\/security"/);
});
