'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const renderer = require('../Resources/app.js');

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

test('thinking and ordinary tools start folded while diff and errors start open', () => {
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

  assert.match(thinking, /^<details class="event thinking-event">/);
  assert.match(tool, /^<details class="event tool-event">/);
  assert.match(diff, /^<details class="event diff-event" open>/);
  assert.match(error, /^<details class="event error-event" open>/);
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

test('quote selection accepts one assistant message and rejects unsafe ranges', () => {
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
  assert.equal(
    renderer.quotePayloadFromSelection(
      selection(textNode(assistantA), textNode(assistantA), 'x'.repeat(20001)),
      { sessionId: 'session-a' }
    ),
    null
  );
});
