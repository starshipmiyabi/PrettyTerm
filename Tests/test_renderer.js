'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const renderer = require('../Resources/app.js');

test('mostly changed 1000-line diffs fit in a 64 MiB JavaScript heap', () => {
  const { spawnSync } = require('node:child_process');
  const script = `
    const r = require(${JSON.stringify(require.resolve('../Resources/app.js'))});
    const a = Array.from({length:1000}, (_, i) => 'old-' + i);
    const b = Array.from({length:1000}, (_, i) => 'new-' + i);
    a[500] = b[500] = 'shared';
    const result = r.diffLines(a.join('\\n'), b.join('\\n'));
    if (result.length !== 1999) process.exit(2);
  `;
  const child = spawnSync(process.execPath, ['--max-old-space-size=64', '-e', script], { encoding: 'utf8' });
  assert.equal(child.status, 0, `diff exceeded heap budget or lost content (${child.signal})`);
});

test('diff reconstruction and edit counts match an independent LCS oracle', () => {
  const values = ['a', 'b', 'c'];
  let seed = 17;
  const random = () => (seed = (seed * 1664525 + 1013904223) >>> 0);
  for (let trial = 0; trial < 250; trial++) {
    const a = Array.from({ length: 1 + random() % 20 }, () => values[random() % 3]);
    const b = Array.from({ length: 1 + random() % 20 }, () => values[random() % 3]);
    const table = Array.from({ length: a.length + 1 }, () => new Uint32Array(b.length + 1));
    for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++) {
      table[i][j] = a[i - 1] === b[j - 1] ? table[i - 1][j - 1] + 1
        : Math.max(table[i - 1][j], table[i][j - 1]);
    }
    const diff = renderer.diffLines(a.join('\n'), b.join('\n'));
    assert.deepEqual(diff.filter(x => x.type !== 'add').map(x => x.text), a);
    assert.deepEqual(diff.filter(x => x.type !== 'remove').map(x => x.text), b);
    assert.equal(diff.filter(x => x.type === 'context').length, table[a.length][b.length]);
  }
});

test('assistant text is flat inside a Reasonix-style turn', () => {
  const html = renderer.renderSession({
    sessionId: 's1',
    model: 'Claude',
    messages: [
      { role: 'user', text: '请修复登录' },
      { role: 'assistant', text: '已经修复。' }
    ]
  });

  assert.match(html, /class="turn"/);
  assert.match(html, /class="turn-prompt"/);
  assert.match(html, /class="assistant-text"/);
  assert.doesNotMatch(html, /class="[^"]*assistant-text[^"]*card/);
});

test('every Claude text output exposes its exact text through a copy button', () => {
  const html = renderer.renderSession({
    sessionId: 'copy-session',
    messages: [
      { role: 'user', text: '给我结果' },
      { role: 'assistant', text: '第一行\n第二行 <完成>' }
    ]
  });

  assert.match(html, /class="assistant-copy-button"/);
  assert.match(html, /data-copy-text="第一行\n第二行 &lt;完成&gt;"/);
  assert.match(html, /<span aria-hidden="true">⧉<\/span>复制<\/button>/);
});

test('a real waiting state renders the animated Terminal-to-Claude signal route', () => {
  const html = renderer.renderSession({
    sessionId: 'waiting-session',
    awaitingReply: true,
    messages: [{ role: 'user', text: '请继续' }]
  });

  assert.match(html, /class="claude-waiting"/);
  assert.match(html, /Claude 正在组织思路/);
  assert.match(html, /class="claude-mark"/);
  assert.match(html, /aria-label="Claude"/);
  assert.equal((html.match(/class="thought-packet"/g) || []).length, 3);
  assert.doesNotMatch(
    renderer.renderSession({ awaitingReply: false, messages: [{ role: 'user', text: '完成' }] }),
    /claude-waiting/
  );
  assert.equal(typeof renderer.setClaudeWaiting, 'function');
});

test('thinking, tools, and per-file diffs start folded while errors start open', () => {
  const thinking = renderer.renderEvent({ kind: 'thinking', text: '分析中' }, {});
  const tool = renderer.renderEvent({ kind: 'tool', toolName: 'Read', text: '读取文件' }, {});
  const diff = renderer.renderEvent({
    kind: 'diff',
    toolName: 'Edit',
    filePath: '/tmp/a.js',
    oldText: 'const a = 1;',
    newText: 'const a = 2;'
  }, {});
  const error = renderer.renderEvent({ kind: 'error', text: '命令失败' }, {});

  assert.match(thinking, /^<details class="event thinking-event"(?: data-message-key="[^"]*")?>/);
  assert.match(tool, /^<details class="event tool-event"(?: data-message-key="[^"]*")?>/);
  assert.match(diff, /^<details class="event diff-event">/);
  assert.match(error, /^<details class="event error-event" open(?: data-message-key="[^"]*")?>/);
});

test('tool activity uses a closed outer group and closed per-call details', () => {
  const html = renderer.renderSession({
    sessionId: 'tool-groups',
    messages: [
      { role: 'user', text: '查一下' },
      { kind: 'tool', toolName: 'ToolSearch', text: 'query one' },
      { kind: 'tool', toolName: 'WebSearch', text: 'result one' },
      { kind: 'tool', toolName: 'WebSearch', text: 'result two' },
      { role: 'assistant', text: '继续检查。' },
      { kind: 'tool', toolName: 'Read', text: '/tmp/a.md' }
    ]
  });

  assert.equal((html.match(/<details class="tool-group"/g) || []).length, 2);
  assert.equal((html.match(/<details class="event tool-event"/g) || []).length, 4);
  assert.match(html, /class="tool-group" data-tool-count="3"><summary>/);
  assert.match(html, /工具调用情况/);
  assert.match(html, /class="tool-group-count">3 次</);
  assert.doesNotMatch(html, /<details class="tool-group"[^>]* open/);
  assert.doesNotMatch(html, /<details class="event tool-event"[^>]* open/);
});

test('each turn ends with one Codex-style edited-files summary', () => {
  const html = renderer.renderSession({
    sessionId: 'session-edits',
    messages: [
      { role: 'user', text: '改一下' },
      { kind: 'diff', filePath: '/tmp/A.m', oldText: 'old', newText: 'new\nextra' },
      { kind: 'diff', filePath: '/tmp/B.m', oldText: '', newText: 'created' },
      { role: 'assistant', text: '完成。' },
      { role: 'user', text: '再解释一下' },
      { role: 'assistant', text: '说明。' }
    ]
  });

  assert.equal((html.match(/data-edit-summary/g) || []).length, 1);
  assert.match(html, /已编辑 2 个文件/);
  assert.match(html, /class="open-local-review"/);
  assert.match(html, /data-session-id="session-edits"/);
  assert.match(html, /data-turn-index="0"/);
  assert.match(html, />A\.m<|>B\.m</);
});

test('renderer switches conversation chrome between Chinese and English', () => {
  const html = renderer.renderSession({
    interfaceLanguage: 'en',
    sessionId: 'session-en',
    messages: [
      { role: 'user', text: 'Change it' },
      { kind: 'thinking', text: 'Checking' },
      { kind: 'diff', filePath: '/tmp/A.m', oldText: 'old', newText: 'new' }
    ]
  });
  assert.match(html, /Thinking/);
  assert.match(html, /Edited 1 files/);
  assert.match(html, />Review</);
  assert.doesNotMatch(html, /已编辑|审阅|思考过程/);
  renderer.setPrettyTermLanguage('zh-Hans');
});

test('large diffs retain exact shared context without a size cutoff', () => {
  const beforeLines = Array.from({ length: 20000 }, (_, index) => `line ${index}`);
  const afterLines = beforeLines.slice();
  afterLines[10000] = 'changed line';
  const before = beforeLines.join('\n');
  const after = afterLines.join('\n');
  const lines = renderer.diffLines(before, after);

  assert.equal(lines.filter(line => line.type === 'context').length, 19999);
  assert.equal(lines.filter(line => line.type === 'remove').length, 1);
  assert.equal(lines.filter(line => line.type === 'add').length, 1);
});

test('terminal residue is removed without deleting useful text', () => {
  const dirty = '\u001b[31m失败\u001b[0m <local-command-stdout>保留这段</local-command-stdout>\n<command-name>npm test</command-name>';
  const clean = renderer.cleanTranscriptText(dirty);

  assert.equal(clean, '失败 保留这段\nnpm test');
  assert.doesNotMatch(clean, /\u001b|\u009b|local-command|command-name/);
});

test('cleanup preserves source code that merely looks like XML', () => {
  const source = '```html\n  <div class="demo">ok</div>\n```\n  if (a < b) return;';

  assert.equal(renderer.cleanTranscriptText(source), source);
});

test('markdown supports links, ordered lists, inline math and multiline display math', () => {
  const html = renderer.renderMarkdown(
    '[文档](https://example.com)\n' +
    '1. 第一项\n' +
    '2. 第二项\n' +
    '价格是 $x+1$。\n' +
    '$$\n' +
    'x^2 + y^2\n' +
    '$$'
  );

  assert.match(html, /<a href="https:\/\/example\.com"[^>]*>文档<\/a>/);
  assert.match(html, /<ol>/);
  assert.match(html, /<li>第一项<\/li>/);
  assert.match(html, /<span class="inline-math">\\\(x\+1\\\)<\/span>。/);
  assert.match(html, /<div class="math-block">\\\[\nx\^2 \+ y\^2\n\\\]<\/div>/);
});

test('file preview compiles Markdown into a standalone rendered document', async () => {
  const html = await renderer.renderFilePreview({
    kind: 'markdown',
    title: 'Guide.md',
    path: '/tmp/Guide.md',
    text: '# Heading\n\n- first\n- second\n\n```js\nconst value = 1;\n```\n\n$x+1$'
  });

  assert.match(html, /class="file-document markdown-document"/);
  assert.match(html, /<h1>Heading<\/h1>/);
  assert.match(html, /<ul><li>first<\/li><li>second<\/li><\/ul>/);
  assert.match(html, /<pre><code class="language-js">const value = 1;<\/code><\/pre>/);
  assert.match(html, /<span class="inline-math">\\\(x\+1\\\)<\/span>/);
  assert.doesNotMatch(html, /># Heading</);
});

test('file preview renders complete escaped source with literal line numbers', async () => {
  const html = await renderer.renderFilePreview({
    kind: 'source',
    title: 'Review.m',
    path: '/tmp/Review.m',
    text: 'if (a < b) {\n  return "<done>";\n}\n'
  });

  assert.match(html, /class="file-document source-document"/);
  assert.equal((html.match(/class="source-line"/g) || []).length, 4);
  assert.match(html, /class="line-number">1<\/span><code>if \(a &lt; b\) \{<\/code>/);
  assert.match(html, /class="line-number">2<\/span><code>  return &quot;&lt;done&gt;&quot;;<\/code>/);
  assert.match(html, /class="line-number">4<\/span><code><\/code>/);
});

test('live LaTeX waits for MathJax startup and serializes every incremental typeset', async () => {
  let releaseStartup;
  let active = 0;
  let maximumActive = 0;
  const calls = [];
  const originalMathJax = globalThis.MathJax;
  globalThis.MathJax = {
    startup: {
      promise: new Promise(resolve => { releaseStartup = resolve; })
    },
    typesetPromise: async targets => {
      active++;
      maximumActive = Math.max(maximumActive, active);
      calls.push(targets.map(target => target.id));
      await new Promise(resolve => setImmediate(resolve));
      active--;
    }
  };

  try {
    const first = renderer.typeset([{ id: 'first-formula' }]);
    const second = renderer.typeset([{ id: 'second-formula' }]);
    await Promise.resolve();
    assert.deepEqual(calls, [], 'typesetting must wait until MathJax startup completes');
    releaseStartup();
    await Promise.all([first, second]);
    assert.deepEqual(calls, [['first-formula'], ['second-formula']]);
    assert.equal(maximumActive, 1, 'incremental MathJax compilation must never overlap');
  } finally {
    if (originalMathJax === undefined) delete globalThis.MathJax;
    else globalThis.MathJax = originalMathJax;
  }
});

test('ordered lists keep numbering across indented continuation paragraphs', () => {
  const html = renderer.renderMarkdown(
    '1. **切 patch**\n' +
    '   到每个 patch 的特征。\n\n' +
    '2. **选 Top-K**\n' +
    '   权重随运动变化。\n' +
    '   光流也会参与。\n\n' +
    '3. **构造全局特征**'
  );

  assert.equal((html.match(/<ol(?:\s|>)/g) || []).length, 1);
  assert.equal((html.match(/<li>/g) || []).length, 3);
  assert.match(html, /<li><strong>切 patch<\/strong><div class="list-continuation">到每个 patch 的特征。<\/div><\/li>/);
  assert.match(html, /<li><strong>选 Top-K<\/strong><div class="list-continuation">权重随运动变化。<\/div><div class="list-continuation">光流也会参与。<\/div><\/li>/);
});

test('Markdown all-one list convention still renders as one sequential list', () => {
  const html = renderer.renderMarkdown('1. 第一项\n   说明一\n1. 第二项\n   说明二');

  assert.equal((html.match(/<ol(?:\s|>)/g) || []).length, 1);
  assert.equal((html.match(/<li>/g) || []).length, 2);
});

test('markdown renders a pipe table as semantic table markup', () => {
  const html = renderer.renderMarkdown(
    '| 项目 | 论文/会议 | 核心思路 |\n' +
    '|---|:---:|---:|\n' +
    '| **DRFusion** | ICML 2026 | 稳定时序漂移 |\n' +
    '| MAVFusion | ECCV 2026 | 轻量推理 |'
  );

  assert.match(html, /<table>/);
  assert.match(html, /<thead><tr><th>项目<\/th><th>论文\/会议<\/th><th>核心思路<\/th><\/tr><\/thead>/);
  assert.match(html, /<tbody><tr><td><strong>DRFusion<\/strong><\/td><td>ICML 2026<\/td><td>稳定时序漂移<\/td><\/tr>/);
  assert.match(html, /<tr><td>MAVFusion<\/td><td>ECCV 2026<\/td><td>轻量推理<\/td><\/tr><\/tbody><\/table>/);
  assert.doesNotMatch(html, /<p>\|/);
});

test('only user inputs exceeding 20 lines collapse while assistant output stays open', () => {
  const twentyLineInput = Array.from({ length: 20 }, (_, index) => `输入 ${index + 1}`).join('\n');
  const twentyOneLineInput = `${twentyLineInput}\n输入 21`;
  const assistantOutput = Array.from({ length: 80 }, (_, index) => `输出 ${index + 1}`).join('\n');

  assert.doesNotMatch(
    renderer.renderEvent({ role: 'user', text: twentyLineInput }, {}),
    /<details class="long-content"/
  );
  assert.match(
    renderer.renderEvent({ role: 'user', text: twentyOneLineInput }, {}),
    /<details class="long-content"/
  );
  assert.doesNotMatch(
    renderer.renderEvent({ role: 'assistant', text: assistantOutput }, {}),
    /<details class="long-content"/
  );
  assert.equal(typeof renderer.setClaudeSession, 'function');
  assert.equal(typeof renderer.appendClaudeMessages, 'function');
});

test('an ordinary multiline Claude reply stays visible instead of looking unsynced', () => {
  const html = renderer.renderEvent({
    role: 'assistant',
    text: Array.from({ length: 30 }, (_, index) => `第 ${index + 1} 行普通回复`).join('\n')
  }, {});

  assert.doesNotMatch(html, /<details class="long-content"/);
  assert.match(html, /第 30 行普通回复/);
});

test('a short 53-line final reply is not mistaken for hidden long content', () => {
  const text = Array.from({ length: 53 }, (_, index) => `短分点 ${index + 1}`).join('\n');
  assert.ok(text.length < 2400, 'fixture must model the real short final reply');

  const html = renderer.renderEvent({ role: 'assistant', text }, {});

  assert.doesNotMatch(html, /<details class="long-content"/);
  assert.match(html, /短分点 53/);
});

test('quote selection accepts unlimited text from one assistant message', () => {
  const assistantA = { closest: selector => selector === '.assistant-text' ? assistantA : null };
  const assistantB = { closest: selector => selector === '.assistant-text' ? assistantB : null };
  const tool = { closest: () => null };
  const textNode = parentElement => ({ nodeType: 3, parentElement });
  const selection = (start, end, text) => ({
    collapsed: false,
    rangeCount: 1,
    getRangeAt: () => ({ startContainer: start, endContainer: end }),
    toString: () => text
  });

  assert.deepEqual(
    renderer.quotePayloadFromSelection(
      selection(textNode(assistantA), textNode(assistantA), '第一行\n第二行'),
      { sessionId: 'session-a' }
    ),
    { text: '第一行\n第二行', sessionId: 'session-a' }
  );
  assert.equal(
    renderer.quotePayloadFromSelection(
      selection(textNode(assistantA), textNode(assistantB), '跨消息'),
      { sessionId: 'session-a' }
    ),
    null
  );
  assert.equal(
    renderer.quotePayloadFromSelection(
      selection(textNode(tool), textNode(tool), '工具结果'),
      { sessionId: 'session-a' }
    ),
    null
  );
  assert.deepEqual(
    renderer.quotePayloadFromSelection(
      selection(textNode(assistantA), textNode(assistantA), 'x'.repeat(20001)),
      { sessionId: 'session-a' }
    ),
    { text: 'x'.repeat(20001), sessionId: 'session-a' }
  );
});

// 追加渲染时原生只发元数据（不含 messages），省掉每次几 MB 的序列化。
// 会话标识一致时才合并增量。
test('metadata-only appends require the loaded session identity', async () => {
  assert.equal(typeof renderer.sessionMatches, 'function');

  // 尚未装载任何会话时没有合并目标。
  assert.equal(renderer.sessionMatches({ sessionId: 's1' }), false);

  await renderer.setClaudeSession({
    sessionId: 's1',
    model: 'Claude',
    messages: [{ role: 'user', text: '第一条' }]
  });

  assert.equal(renderer.sessionMatches({ sessionId: 's1' }), true);
  assert.equal(renderer.sessionMatches({ sessionId: 's2' }), false);
  assert.equal(renderer.sessionMatches({}), false);
  assert.equal(renderer.sessionMatches(null), false);

  // 会话不匹配时保持当前内容，不触发整页重建。
  const before = renderer.renderSession;
  await renderer.appendClaudeMessages({ sessionId: 's2', model: 'Claude' }, [
    { role: 'assistant', text: '不该出现' }
  ]);
  assert.equal(typeof before, 'function');
  assert.equal(renderer.sessionMatches({ sessionId: 's1' }), true,
    'a rejected metadata-only append must not clobber the loaded session');

  // 同一会话的元数据追加正常合并，并且不需要 messages 字段。
  await renderer.appendClaudeMessages({ sessionId: 's1', model: 'Claude' }, [
    { role: 'assistant', text: '第二条' }
  ]);
  assert.equal(renderer.sessionMatches({ sessionId: 's1' }), true);
});

test('AskUserQuestion renders a clickable card, not a generic tool bubble', () => {
  const html = renderer.renderEvent({
    kind: 'question',
    toolUseId: 'toolu_1',
    messageKey: 'k1',
    questions: [
      { question: '接下来怎么走？', header: 'H', multiSelect: false, options: [
        { label: '方案 A', description: '<script>危险</script>' },
        { label: '方案 B', description: '备选' }
      ] },
      { question: '要不要顺带测试？', header: 'QA', multiSelect: true, options: [
        { label: '加单测' }
      ] }
    ]
  }, {});

  assert.match(html, /class="question-card"/);
  assert.doesNotMatch(html, /class="event tool-event"/);
  assert.match(html, /data-tool-use-id="toolu_1"/);
  assert.match(html, /data-question-index="0" data-multi="0"/);
  assert.match(html, /data-question-index="1" data-multi="1"/);
  assert.match(html, /class="question-submit"/);
  assert.match(html, /class="question-custom-input"/);
  assert.match(html, /class="question-option-mark"/);
  assert.match(html, /class="question-option-check"/);
  assert.match(html, /class="question-submit-arrow"/);
  assert.match(html, /aria-pressed="false"/);
  // 危险字符必须被转义，不能原样注入 DOM
  assert.doesNotMatch(html, /<script>危险<\/script>/);
  assert.match(html, /&lt;script&gt;危险&lt;\/script&gt;/);
});

test('an already-answered question displays the recorded answer with no input controls', () => {
  const html = renderer.renderEvent({
    kind: 'question',
    answered: true,
    answerText: '接下来怎么走？：方案 A'
  }, {});

  assert.match(html, /class="question-card answered"/);
  assert.match(html, /方案 A/);
  assert.doesNotMatch(html, /question-option/);
  assert.doesNotMatch(html, /question-submit/);
});
