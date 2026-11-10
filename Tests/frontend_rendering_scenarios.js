const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const until = async (condition, message) => {
  for (let i = 0; i < 300; i++) {
    if (condition()) return;
    await wait(30);
  }
  throw new Error(message);
};
const countNodes = (root = document) => {
  let total = root.querySelectorAll('*').length;
  for (const element of root.querySelectorAll('*')) if (element.shadowRoot) total += countNodes(element.shadowRoot);
  return total;
};
const report = (scene, extra = {}) => window.webkit.messageHandlers.ptPerformance.postMessage({ scene, nodes: countNodes(), ...extra });
const code = (prefix, length) => Array.from({ length }, (_, i) => `export const ${prefix}_${i} = "value ${i}";`).join('\n');
const tab = {
  id: 'perf-tab', sessionId: 'perf-session', title: 'Rendering test', cwd: '/tmp/session-cwd',
  fileTreeRootPath: '/tmp/session-cwd', activeToolPageKind: 'review', panelExpanded: true,
  overviewExpanded: false, fileToolPageOpen: false, reviewToolPageOpen: true,
};
window.setPrettyTermWorkspace({
  activeTabId: tab.id, selectedSessionId: tab.sessionId, floatingSessionId: '', floatingVisible: false, tabs: [tab],
});
await window.setClaudeSession({ sessionId: tab.sessionId, messages: [] });
const files = Array.from({ length: 12 }, (_, i) => ({
  path: `src/file-${i}.ts`, binary: false, statusCode: 'A', statusLabel: 'Added', added: 800, removed: 0,
  patch: `diff --git a/src/file-${i}.ts b/src/file-${i}.ts\nnew file mode 100644\n--- /dev/null\n+++ b/src/file-${i}.ts\n@@ -0,0 +1,800 @@\n${code('file' + i, 800).split('\n').map((line) => '+' + line).join('\n')}\n`,
}));
window.setPrettyTermGitState({ reviewMode: 'git', observedDirectory: '/tmp/prettyterm-review', files });
await until(() => document.querySelector('[data-pt-review-pane] diffs-container')?.shadowRoot?.querySelector('[data-line]'), 'Git diff must render');
await wait(600);
const reviewNodes = countNodes(document.querySelector('[data-pt-review-pane]'));
report('git-review-9600-lines', { reviewNodes });
if (assertOptimized) {
  assert(reviewNodes < 12000, `Diff must render a viewport of lines, got ${reviewNodes} nodes`);
  const open = document.querySelector('[data-pt-open-review-source]');
  assert(open, 'Git review must offer Open source');
  open.click();
  await wait(200);
  assert(document.querySelector('[data-pt-review-pane] diffs-container'), 'Opening source must preserve the expanded diff');
}
const scroller = document.querySelector('[data-pt-review-pane] .pt-diff-viewport') ||
  [...document.querySelector('[data-pt-review-pane]').children].at(-1);
scroller.scrollTop = scroller.scrollHeight;
await until(() => {
  const containers = document.querySelectorAll('[data-pt-review-pane] diffs-container');
  return [...containers].at(-1)?.shadowRoot?.textContent.includes('file11_799');
}, 'Last file and line must remain accessible after scrolling');
window.setPrettyTermGitState({ reviewMode: 'turn', editEvents: [{
  filePath: '/tmp/prettyterm-review/turn-file.ts', oldText: code('old', 1200), newText: code('new', 1200),
}] });
await until(() => document.querySelector('[data-pt-review-pane] diffs-container')?.shadowRoot?.querySelector('[data-line]'), 'Turn diff must render');
await wait(300);
report('turn-review-2400-lines');
if (assertOptimized) {
  const open = document.querySelector('[data-pt-open-review-source]');
  assert(open, 'Turn review must offer Open source');
  open.click();
  scroller.scrollTop = scroller.scrollHeight;
  await until(() => document.querySelector('[data-pt-review-pane] diffs-container')?.shadowRoot?.textContent.includes('new_1199'), 'Turn diff last line must remain accessible');
  document.querySelector('[data-pt-review-pane] [aria-label="Split Diff"]').click();
  await until(() => document.querySelector('[data-pt-review-pane] [aria-label="Unified Diff"]'), 'Split view must stay available');
}
window.setPrettyTermWorkspace({
  activeTabId: tab.id, selectedSessionId: tab.sessionId, floatingSessionId: '', floatingVisible: false,
  tabs: [{ ...tab, panelExpanded: false, overviewExpanded: false }],
});
// Distinct code blocks exercise the upstream rendered-HTML cache across sessions.
for (let session = 0; session < 30; session++) {
  await window.setClaudeSession({ sessionId: tab.sessionId, messages: [
    { role: 'user', messageKey: 'u' + session, text: 'Show code ' + session },
    { role: 'assistant', messageKey: 'a' + session, text: '```typescript\n' + code('session' + session, 500) + '\n```' },
  ] });
  await until(() => document.querySelector('[data-pt-assistant-prose] .shiki')?.textContent.includes(`session${session}_499`), 'Code block must render fully');
}
await window.setClaudeSession({ sessionId: tab.sessionId, messages: [
  { role: 'user', messageKey: 'done-user', text: 'Done' },
  { role: 'assistant', messageKey: 'done-answer', text: 'Complete.' },
] });
await until(() => document.querySelector('[data-pt-assistant-prose]')?.textContent.includes('Complete.'), 'Final conversation must render');
await wait(500);
report('after-30-long-code-sessions');
return true;
