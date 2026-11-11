const assert = require('node:assert/strict');
const path = require('node:path');
const { TranscriptProjection, groupAssistantTimeline } = require(path.resolve(process.argv[2]));

function orderedMessages(prefix) {
  return [
    { role: 'assistant', messageKey: `${prefix}-before`, text: 'Before tool' },
    {
      role: 'tool',
      kind: 'tool',
      messageKey: `${prefix}-call`,
      text: 'command input',
      toolInput: { command: 'printf result' },
      toolName: 'Bash',
      toolUseId: `${prefix}-tool-id`,
    },
    { role: 'assistant', messageKey: `${prefix}-middle`, text: 'Between tools' },
    {
      role: 'tool',
      messageKey: `${prefix}-result`,
      text: 'command output',
      toolName: '工具结果',
      toolUseId: `${prefix}-tool-id`,
    },
    {
      role: 'assistant',
      kind: 'thinking',
      messageKey: `${prefix}-thinking`,
      text: 'Reasoning detail',
    },
    {
      role: 'assistant',
      kind: 'question',
      messageKey: `${prefix}-question`,
      questions: [{ question: 'Choose one' }],
      toolUseId: `${prefix}-question-id`,
    },
    { role: 'assistant', messageKey: `${prefix}-after`, text: 'After tool' },
  ];
}

function assertOrderedTurn(turn) {
  assert.ok(turn);
  assert.deepEqual(
    turn.timeline.map((item) => item.kind),
    ['answer', 'step', 'answer', 'step', 'question', 'answer'],
  );
  assert.deepEqual(
    turn.timeline.filter((item) => item.kind === 'answer').map((item) => item.answer.text),
    ['Before tool', 'Between tools', 'After tool'],
  );
  assert.equal(turn.steps[0].resultText, 'command output');
  assert.equal(turn.steps[1].kind, 'thinking');
  assert.equal(turn.questionBlocks[0].questions[0].question, 'Choose one');
}

function assertWorkflowGroupsSplitAtProse(turn) {
  const groups = groupAssistantTimeline([
    { kind: 'step', step: turn.steps[0] },
    { kind: 'step', step: { ...turn.steps[0], id: 'second-step' } },
    { kind: 'answer', answer: turn.answerBlocks[1] },
    { kind: 'step', step: { ...turn.steps[1], id: 'third-step' } },
    { kind: 'step', step: { ...turn.steps[1], id: 'fourth-step' } },
  ]);
  assert.deepEqual(groups.map((item) => item.kind), ['stepGroup', 'answer', 'stepGroup']);
  assert.deepEqual(
    groups.filter((item) => item.kind === 'stepGroup').map((item) => [item.id, item.steps.length]),
    [[turn.steps[0].id, 2], ['third-step', 2]],
  );
}

const persisted = new TranscriptProjection('en');
persisted.replace({
  sessionId: 'persisted-session',
  messages: [
    { role: 'user', messageKey: 'persisted-user', text: 'Prompt' },
    ...orderedMessages('persisted'),
  ],
});
assertOrderedTurn(persisted.row('turn:persisted-user'));
assertWorkflowGroupsSplitAtProse(persisted.row('turn:persisted-user'));

const live = new TranscriptProjection('en');
live.replace({
  sessionId: 'live-session',
  messages: [{ role: 'user', messageKey: 'live-user', text: 'Prompt' }],
});
live.stream({
  active: true,
  generation: 'generation-1',
  revision: 1,
  sessionId: 'live-session',
  messages: orderedMessages('live'),
});
assertOrderedTurn(live.row('turn:live-user'));
assertWorkflowGroupsSplitAtProse(live.row('turn:live-user'));

const fileChanges = new TranscriptProjection('en');
fileChanges.replace({
  sessionId: 'file-change-session',
  messages: [
    { role: 'user', messageKey: 'file-change-user', text: 'Prompt' },
    {
      added: 2,
      filePath: '/tmp/edit.py',
      kind: 'diff',
      newText: 'a\nB\nc',
      oldText: 'a\nb',
      removed: 1,
      role: 'tool',
      toolName: 'Edit',
    },
    {
      added: 3,
      filePath: '/tmp/write.py',
      kind: 'diff',
      newText: 'one\ntwo\nthree\n',
      oldText: '',
      removed: 0,
      role: 'tool',
      toolName: 'Write',
    },
  ],
});
const fileChangeTurn = fileChanges.row('turn:file-change-user');
assert.ok(fileChangeTurn);
assert.match(fileChangeTurn.steps[0].title, /edit\.py \(\+2 -1\)$/);
assert.match(fileChangeTurn.steps[1].title, /write\.py \(\+3 -0\)$/);

console.log('PTTranscriptProjectionTests passed');
