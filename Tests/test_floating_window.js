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
  assert.match(buildMethod[0], /fileDropHandler/);
  assert.match(buildMethod[0], /chooseFloatingAttachments:/);
  assert.match(source, /sendOutgoingMessage:[\s\S]*forSessionID:/);
  assert.match(source, /bridgeForSessionID:sessionID/);
  assert.match(source, /sendFloatingMessage:[\s\S]*floatingPendingImagePNGsForClaude/);
  assert.match(source, /windowWillClose:[\s\S]*_floatingSessionID\s*=\s*nil/);
});

test('workspace tabs retain independent Terminal bridges and composer state', () => {
  assert.match(source, /@interface PTWorkspaceTab[\s\S]*PTClaudeBridge \*bridge/);
  assert.match(source, /NSMutableArray<PTWorkspaceTab \*> \*_workspaceTabs/);
  assert.match(source, /createWorkspaceTab[\s\S]*\[\[PTClaudeBridge alloc\] init\]/);
  assert.match(source, /activateWorkspaceTab:[\s\S]*_bridge = tab\.bridge/);
  assert.match(source, /saveActiveWorkspaceTabState[\s\S]*tab\.draft|_activeWorkspaceTab\.draft/);
  assert.match(source, /tab\.pendingImages/);
  assert.match(source, /tab\.pendingFiles/);
  assert.match(source, /addWorkspaceTab:/);
  assert.match(source, /＋  新标签/);
  assert.match(source, /closeWorkspaceTab:[\s\S]*\[closingTab\.bridge stop\]/);
  assert.match(source, /closeWorkspaceTab:[\s\S]*removeObjectAtIndex:index/);
  assert.match(source, /closeWorkspaceTab:[\s\S]*activateWorkspaceTab:_workspaceTabs\[nextIndex\]/);
  assert.match(source, /closeButton\.action = @selector\(closeWorkspaceTab:\)/);
  assert.match(source, /titleLabel\.leadingAnchor constraintEqualToAnchor:item\.leadingAnchor constant:14/);
  assert.match(source, /for \(PTWorkspaceTab \*tab in _workspaceTabs\.copy\)[\s\S]*\[tab\.bridge stop\]/);
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

test('successful messages show one real waiting state until transcript activity arrives', () => {
  assert.match(source, /beginAwaitingClaudeReplyForSessionID:self->_selectedSession\.sessionID/);
  assert.match(source, /beginAwaitingClaudeReplyForSessionID:self->_floatingSessionID/);
  assert.match(source, /reconcileAwaitingClaudeReplyWithSession:/);
  assert.match(source, /window\.setClaudeWaiting/);
  assert.match(source, /@"awaitingReply"/);
});

test('Terminal connection state never makes conversation controls unavailable', () => {
  assert.match(agentSource, /return self\.selectedSessionID\.length > 0/);
  assert.doesNotMatch(agentSource,
    /commandsEnabled[\s\S]*?bridgeRunning|commandsEnabled[\s\S]*?boundSessionID/);
  assert.match(source, /_composerTextView\.editable = ready/);
  assert.match(source, /_sendButton\.enabled = ready/);
  assert.match(source, /_floatingComposerTextView\.editable = ready/);
  assert.match(source, /_floatingSendButton\.enabled = ready/);
  assert.doesNotMatch(source, /_composerTextView\.editable = ready && !awaiting/);
  assert.doesNotMatch(source, /_floatingComposerTextView\.editable = ready && !awaiting/);
  assert.doesNotMatch(source, /只读|未同步|请先同步|Read only|Conversation not synced/);

  const chooseMainAttachments = source.match(
    /- \(void\)chooseAttachments:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const chooseFloatingAttachments = source.match(
    /- \(void\)chooseFloatingAttachments:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const compact = source.match(
    /- \(void\)compactConversation:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const model = source.match(
    /- \(void\)changeModel:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.doesNotMatch(chooseMainAttachments, /commandsEnabled|bridgeForSessionID/);
  assert.doesNotMatch(chooseFloatingAttachments, /commandsEnabled|bridgeForSessionID/);
  assert.doesNotMatch(compact, /commandsEnabled/);
  assert.doesNotMatch(model, /commandsEnabled/);
});

test('both windows append new JSONL messages without automatic full-snapshot recovery', () => {
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
  assert.doesNotMatch(mainRender[0], /PTSessionInfo \*latest = self->_selectedSession/);
  assert.doesNotMatch(floatingRender[0], /sessionWithID:self->_floatingSessionID/);
  assert.doesNotMatch(mainRender[0], /_renderedSessionID = nil/);
  assert.doesNotMatch(floatingRender[0], /_floatingRenderedSessionID = nil/);
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

test('edited-turn summaries bridge both webviews to transcript-local review without Git', () => {
  const registrations = source.match(/addScriptMessageHandler:self name:@"openTranscriptEditReview"/g) || [];
  assert.equal(registrations.length, 2);
  const method = source.match(
    /- \(void\)openTranscriptEditReviewForSessionID:[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(method, /transcriptEditEventsForSession:/);
  assert.match(method, /showTranscriptEditReviewWithEvents:/);
  assert.doesNotMatch(method, /refreshGitDiff|PTRunGit|PTGitReviewSnapshotForDirectory/);
  assert.match(source, /PTTranscriptEditReviewAttributedString/);
});

test('conversation viewport preserves a character anchor while inspector width reflows text', () => {
  const renderer = fs.readFileSync(
    path.resolve(__dirname, '../Resources/app.js'),
    'utf8'
  );
  assert.match(renderer, /caretRangeFromPoint/);
  assert.match(renderer, /function captureViewportAnchor\(/);
  assert.match(renderer, /function restoreViewportAnchor\(/);
  assert.match(renderer, /addEventListener\('resize'/);
  assert.match(renderer, /scrollBy\(0, top - anchor\.top\)/);
});

test('closing a tool workspace removes it before restoring the inspector', () => {
  const method = source.match(
    /- \(void\)setToolWorkspaceExpanded:\(BOOL\)expanded animated:\(BOOL\)animated \{[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const removals = [...method.matchAll(/removeArrangedSubview:/g)].map(match => match.index);
  const restores = [...method.matchAll(/restoreInspectorAfterToolWorkspaceCollapseIfNeeded:/g)]
    .map(match => match.index);
  assert.equal(removals.length, 2);
  assert.equal(restores.length, 2);
  assert.ok(removals[0] < restores[0]);
  assert.ok(removals[1] < restores[1]);
});

test('Git publishing accepts a commit message as an argument and permits authentication prompts', () => {
  assert.match(source, /placeholderString = PTL\(@"提交信息", @"Commit message"\)/);
  assert.match(source, /message\.length > 0/);
  assert.match(source, /@\[@"commit", @"-m", message\]/);
  assert.match(source, /@\[@"push"\]/);
  assert.doesNotMatch(source, /GIT_TERMINAL_PROMPT/);
  assert.match(source, /commitAndPushGitChanges:/);
  assert.match(source, /PTL\(@"包含未暂存的更改", @"Include unstaged changes"\)/);
  assert.doesNotMatch(source, /git commit[^\n]*\$|git push[^\n]*\$/);
});

test('both composers use custom rounded surfaces and animate attachment expansion', () => {
  assert.match(source, /PTComposerDropSurfaceView/);
  assert.match(source, /PTAnimatedButton/);
  assert.match(source, /_composerHeightConstraint\s*=\s*\[composerBar\.heightAnchor constraintEqualToConstant:112\]/);
  assert.match(source, /_floatingComposerHeightConstraint\s*=\s*\[composerBar\.heightAnchor constraintEqualToConstant:108\]/);
  assert.match(source, /CGFloat composerHeight = hasAttachments \? 160 : 112/);
  assert.match(source, /_floatingComposerHeightConstraint\.constant\s*=\s*hasAttachments\s*\?\s*156\s*:\s*108/);
  assert.match(source, /CATransform3DMakeScale\(0\.955, 0\.955, 1\)/);
});

test('file attachments use non-interactive attach markers in both composers', () => {
  const mainSend = source.match(
    /- \(void\)sendMessage:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  const floatingSend = source.match(
    /- \(void\)sendFloatingMessage:\(id\)sender[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(agentSource, /<attach>%@<\/attach>/);
  assert.match(mainSend, /PTMessageByAppendingClaudeAttachMarkers/);
  assert.match(floatingSend, /PTMessageByAppendingClaudeAttachMarkers/);
  assert.doesNotMatch(mainSend, /PTMessageByAppendingClaudeFileReferences/);
  assert.doesNotMatch(floatingSend, /PTMessageByAppendingClaudeFileReferences/);
});

test('dragged and selected images preserve PNG pixels and submit without a confirmation gate', () => {
  assert.match(source, /PTPNGDataForImageFileURL/);
  assert.match(source, /if \(isPNG\) return source/);
  assert.match(source, /@"pngData": pngData/);
  assert.match(source, /PTWritePNGDataToPasteboard/);
  assert.match(source, /BOOL sent = attached && \[self sendMessage:message\]/);
  const imageSend = source.match(
    /- \(BOOL\)sendMessage:\(NSString \*\)message withImagePNGs:\(NSArray<NSData \*> \*\)imagePNGs \{[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(imageSend, /PTRestorePasteboard[\s\S]*return sent/);
  assert.doesNotMatch(imageSend, /PTRestorePasteboard[\s\S]*if \(!attached\)[\s\S]*sendMessage/);
  assert.doesNotMatch(imageSend,
    /boundTerminalContents|PTRunLoopUntil|PTTerminalImageMarkerCount|未确认图片附件|acknowledged/);
});

test('composer options drive real Claude model and effort commands', () => {
  assert.match(source, /showComposerOptions:/);
  assert.match(source, /PTEffortSlider/);
  assert.match(source, /@"\/effort %@"/);
  assert.match(source, /@"\/model %@"/);
  assert.match(source, /PTMessageByAppendingClaudeAttachMarkers/);
  assert.doesNotMatch(source, /_composerEffortButton\.bezelStyle\s*=/);
  const slider = source.match(/@implementation PTEffortSlider[\s\S]*?@end/)?.[0] || '';
  assert.match(slider, /NSPanGestureRecognizer/);
  assert.match(slider, /NSClickGestureRecognizer/);
  assert.match(slider, /shouldRequireFailureOfGestureRecognizer:/);
  assert.match(slider, /handleEffortPan:/);
  assert.match(slider, /handleEffortClick:/);
  assert.match(slider, /dispatch_async\(dispatch_get_main_queue\(\)/);
  assert.doesNotMatch(slider, /nextEventMatchingMask/);
  const changeEffort = source.match(/- \(void\)changeComposerEffort:[\s\S]*?(?=\n- \([^\n]+\))/)?.[0] || '';
  assert.doesNotMatch(changeEffort, /showComposerEffortPage:/);
  assert.match(changeEffort, /sendOutgoingMessage:/);
  const changeComposerModel = source.match(/- \(void\)changeComposerModel:[\s\S]*?(?=\n- \([^\n]+\))/)?.[0] || '';
  assert.match(changeComposerModel, /sendOutgoingMessage:/);
});

test('the MCP question panel contains no native AppKit button or text-field chrome', () => {
  assert.match(source, /@interface PTQuestionOptionButton\s*:\s*PTAnimatedButton/);
  assert.match(source, /@implementation PTFlippedView[\s\S]*isFlipped\s*\{\s*return YES/);
  const panel = source.match(/- \(void\)buildQuestionPanelIfNeeded[\s\S]*?(?=\n- \(void\)closeQuestionPanel:)/)?.[0] || '';
  assert.match(panel, /NSWindowStyleMaskFullSizeContentView/);
  assert.match(panel, /standardWindowButton:NSWindowCloseButton\]\.hidden\s*=\s*YES/);
  assert.match(panel, /PTAnimatedButton \*submitButton/);
  assert.match(panel, /PTFlippedView \*document/);
  assert.doesNotMatch(panel, /bezelStyle\s*=\s*NSBezelStyleRounded/);
  const block = source.match(/- \(NSView \*\)buildQuestionBlockForQuestion:[\s\S]*?(?=\n- \(void\)toggleQuestionOption:)/)?.[0] || '';
  assert.match(block, /customField\.bordered\s*=\s*NO/);
  assert.match(block, /customField\.focusRingType\s*=\s*NSFocusRingTypeNone/);
  assert.match(block, /questionOptionButtonWithLabel:label description:description index:/);
  assert.doesNotMatch(block, /NSTextFieldRoundedBezel/);
});

test('production sending keeps both single-line and multiline messages on the matched Terminal channel', () => {
  const sendMethod = source.match(/- \(BOOL\)sendMessage:\(NSString \*\)message \{[\s\S]*?\n\}/)?.[0] || '';
  assert.match(sendMethod, /\? \[self sendMultilineMessage:message\]/);
  assert.match(sendMethod, /\[self sendToTerminal:PTNormalizedTerminalPasteText\(message\)\][\s\S]*\[self sendReturnToTerminal\]/);
  assert.doesNotMatch(sendMethod, /pasteAndSubmitMultilineMessage/);
  assert.doesNotMatch(sendMethod, /AXIsProcessTrusted/);
  assert.match(source, /markerAfter >= 0 && markerAfter != markerBefore/);
  assert.match(agentSource, /do script \\\"\\\" in theTab/);
  assert.match(agentSource, /if processName is \\\"claude\\\" then set isClaudeProcess to true/);
  assert.doesNotMatch(agentSource, /contains \\\"laude\\\"/);
  assert.doesNotMatch(agentSource, /do script \(ASCII character 13\) in theTab/);
});

test('Claude output can be copied and an active reply can be interrupted with Escape', () => {
  assert.equal((source.match(/addScriptMessageHandler:self name:@"copyAssistantOutput"/g) || []).length, 2);
  assert.match(source, /NSPasteboardTypeString/);
  assert.match(source, /- \(BOOL\)sendEscape/);
  assert.match(source, /PTTerminalAutomationActionInterruptEscape/);
  assert.ok(agentSource.includes('tell application \\"System Events\\" to key code 53'));
  assert.match(source, /_sendButton\.action = awaiting[\s\S]*stopSelectedClaudeOutput:/);
  assert.match(source, /_floatingSendButton\.action = awaiting[\s\S]*stopFloatingClaudeOutput:/);
});

test('Claude.ai Remote Control sends the exact slash command through the selected conversation', () => {
  assert.match(source, /PTWarmButton\(@"Remote", self, @selector\(enableRemoteControl:\)\)/);
  assert.match(source, /_remoteButton\.enabled = ready/);
  const remoteMethod = source.match(
    /- \(void\)enableRemoteControl:[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(remoteMethod, /sendOutgoingMessage:@"\/remote-control"/);
  assert.match(remoteMethod, /forSessionID:_selectedSession\.sessionID/);
  assert.doesNotMatch(remoteMethod, /sendToTerminal:/);
});

test('the Compact control sends only the exact slash command through the selected conversation', () => {
  assert.match(source, /PTWarmButton\(@"Compact", self, @selector\(compactConversation:\)\)/);
  assert.match(source, /_compactButton\.enabled = ready/);
  const compactMethod = source.match(
    /- \(void\)compactConversation:[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(compactMethod, /sendOutgoingMessage:@"\/compact"/);
  assert.match(compactMethod, /forSessionID:_selectedSession\.sessionID/);
  assert.doesNotMatch(compactMethod, /sendToTerminal:/);
});

test('context Details stays clickable without sending a slash command when categories are missing', () => {
  const contextMethod = source.match(
    /- \(void\)toggleContextDetail:[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(source, /_contextDisclosureButton\.enabled\s*=\s*YES/);
  assert.doesNotMatch(contextMethod, /if\s*\(!_contextDisclosureButton\.enabled\)\s*return/);
  assert.doesNotMatch(contextMethod, /sendOutgoingMessage:|sendMessage:|@"\/context"/);
  assert.match(contextMethod, /_selectedSession\.contextBreakdown\.count\s*>\s*0/);
  assert.doesNotMatch(source, /PTEstimateContextBreakdown|PTEstimateMemoryFileTokens|PTEstimateSkillsTokens/);
});

test('the top-left app identity shows the running bundle version and build', () => {
  assert.match(source, /bundleInfo\[@"CFBundleShortVersionString"\]/);
  assert.match(source, /bundleInfo\[@"CFBundleVersion"\]/);
  assert.match(source, /visibleAppVersion = \[NSString stringWithFormat:@"%@ · v%@ \(%@\)"/);
  assert.match(source, /\[self label:visibleAppVersion size:17/);
});

test('interface language picker persists Chinese or English and rebuilds without dropping drafts', () => {
  const method = source.match(
    /- \(void\)changeInterfaceLanguage:[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(source, /PTInterfaceLanguageDefaultsKey/);
  assert.match(source, /addItemWithTitle:@"中文"/);
  assert.match(source, /addItemWithTitle:@"English"/);
  assert.match(method, /NSString \*draft = _composerTextView\.string/);
  assert.match(method, /\[self buildWindow\]/);
  assert.match(method, /_composerTextView\.string = draft/);
  assert.match(source, /@"interfaceLanguage": PTInterfaceLanguageCode\(\)/);
});

test('changed-file buttons accept the first click after Finder deactivates the app', () => {
  assert.match(source, /@interface PTFirstMouseButton : NSButton/);
  assert.match(source, /acceptsFirstMouse:[\s\S]*return YES/);
  assert.match(source, /PTAnimatedButton \*button/);
  assert.match(source, /PTWarmButton\(@"", self, @selector\(revealChangedFile:\)\)/);
  assert.match(source, /existingChangedFilesFromFiles:/);
  assert.match(source, /showEmptyChangedFilesState/);
});

test('Git diff observes remembered transcript directories without changing Claude Code cwd', () => {
  assert.match(source, /NSMutableOrderedSet<NSString \*> \*accessedDirectories/);
  assert.match(source, /session\.accessedDirectories = accessedDirectories\.array/);
  assert.match(source, /PTGitObservedDirectories/);
  assert.match(source, /PTGitReviewSnapshotForDirectory/);
  assert.match(source, /@"--unified=3"/);
  assert.match(source, /展开 Git 审阅/);
  assert.match(source, /不会改变 Claude Code/);
  assert.match(source, /Claude Code 执行 \/add-dir/);
  assert.match(source, /removeSelectedGitDirectory:/);
  assert.match(source, /PTGitSuppressedDirectories/);
  assert.match(source, /仅手动重新添加可恢复/);
  assert.doesNotMatch(source, /allowRediscoveryOfGitDirectoriesForNewSession/);
  assert.match(source, /replaceGitReviewDocument:/);
  assert.match(source, /NSAnimationContext runAnimationGroup/);
  assert.match(source, /NSProgressIndicatorStyleSpinning/);
});

test('active transcripts parse only appended JSONL bytes', () => {
  assert.match(source, /PTReadFileDataFromOffset/);
  assert.match(source, /previousParsedSize/);
  assert.match(source, /PTParseSessionAppending/);
  assert.match(source, /@"parsedSize"/);
});

test('selected transcript writes reparse only that file for immediate add-dir discovery', () => {
  const watchMethod = source.match(
    /- \(void\)watchSelectedSessionTranscript[\s\S]*?(?=\n- \([^\n]+\))/
  )?.[0] || '';
  assert.match(watchMethod, /refreshChangedPath:path/);
  assert.match(watchMethod, /\[self applySessions:updated\]/);
  assert.doesNotMatch(watchMethod, /\[self->_store refresh\]/);
});

test('session context menu opens the recorded project folder directly', () => {
  assert.match(source, /@"打开项目文件夹", @"Open project folder"/);
  assert.match(source, /action:@selector\(openSessionProjectFolder:\)/);
  assert.match(source, /NSString \*projectPath = session\.cwd\.stringByStandardizingPath/);
  assert.match(source, /openURL:\[NSURL fileURLWithPath:path isDirectory:YES\]/);
});

test('plan usage updates only from per-response status line snapshots', () => {
  assert.doesNotMatch(source, /SecItemCopyMatching|AXIsProcessTrusted|kAXTrustedCheckOptionPrompt/);
  assert.doesNotMatch(source, /api\/oauth\/usage|find-generic-password/);
  assert.doesNotMatch(source, /@"-p", @"\/usage"/);
  assert.doesNotMatch(source, /usageRefreshTimer|refreshClaudeUsage/);
  assert.match(source, /PTClaudeUsageSnapshotDirectory/);
  assert.match(source, /startWatchingClaudeUsageSnapshots/);
  assert.match(source, /PTClaudePlanUsageFromStatusLineSnapshot\(snapshot, sessionID\)/);
  assert.match(source, /\[_usageSnapshotWatcher watchFileAtPath:directory onChange:/);
  assert.match(source, /_inspectorFiveHourCaption\.stringValue\s*=\s*fiveCountdown/);
  assert.match(source, /_inspectorSevenDayCaption\.stringValue\s*=\s*sevenCountdown/);
  assert.doesNotMatch(source, /PTL\(@"%@后重置",\s*@"resets in %@"\)/);
});
