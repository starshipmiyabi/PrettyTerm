(async () => {
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  const session = (id, messages) => ({ sessionId: id, messages });
  const formula = { role: 'assistant', text: '$x^2 + y^2$' };
  await MathJax.startup.promise;
  // The native caller discards the result. Serializing this DOM used to allocate
  // a full, post-MathJax copy of the conversation on every append.
  const content = document.getElementById('content');
  const htmlDescriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
  let serialized = 0;
  Object.defineProperty(content, 'innerHTML', {
    configurable: true,
    get() { serialized++; return htmlDescriptor.get.call(this); },
    set(value) { htmlDescriptor.set.call(this, value); }
  });
  await setClaudeSession(session('serialization', [formula]));
  await appendClaudeMessages({ sessionId: 'serialization' }, [formula]);
  delete content.innerHTML;
  check(serialized === 0, `render callbacks unnecessarily serialized the whole DOM ${serialized} times`);
  for (let i = 0; i < 20; i++) {
    await setClaudeSession(session('formula-' + i, [formula]));
  }
  const retained = Array.from(MathJax.startup.document.math).length;
  check(retained === 1, `20 replacements retain ${retained} MathItems instead of 1`);
  check(document.querySelectorAll('mjx-container').length === 1, 'current formula must stay rendered');

  const operations = [];
  for (let i = 0; i < 10; i++) {
    operations.push(setClaudeSession(session('rapid-' + i, [formula])));
    operations.push(appendClaudeMessages({ sessionId: 'rapid-' + i }, [formula]));
  }
  await Promise.all(operations);
  check(Array.from(MathJax.startup.document.math).length === 2, 'rapid switches must release old formulas');
  check(document.querySelectorAll('mjx-container').length === 2, 'rapid append must compile both formulas');
  await PrettyTermRenderer.setPrettyTermLanguage('en');
  check(Array.from(MathJax.startup.document.math).length === 2, 'language rebuild must release old formulas');
  check(document.querySelectorAll('mjx-container').length === 2, 'language rebuild must compile formulas');

  const edit = { kind: 'diff', filePath: '/tmp/old.txt', oldText: 'a', newText: 'b\nc' };
  await setClaudeSession(session('history', [
    { role: 'user', text: 'first' }, edit,
    { role: 'user', text: 'second' }, formula
  ]));
  const historical = document.querySelector('[data-edit-summary]');
  await appendClaudeMessages({ sessionId: 'history' }, [{ role: 'assistant', text: 'new reply' }]);
  check(document.querySelector('[data-edit-summary]') === historical,
    'unrelated append must preserve the historical edit summary node');
  await appendClaudeMessages({ sessionId: 'history' }, [
    { ...edit, filePath: '/tmp/new.txt', newText: 'z' }
  ]);
  check(document.querySelectorAll('[data-edit-summary]').length === 2, 'new edit must update its own turn');
  check(document.querySelector('[data-edit-summary]') === historical, 'new edit must preserve older turns');
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  const until = async (predicate, message) => {
    for (let i = 0; i < 200; i++) {
      if (predicate()) return;
      await pause(20);
    }
    check(false, message);
  };
  const longHistory = Array.from({ length: 120 }, (_, i) => [
    { role: 'user', text: `QUESTION-${i}` },
    { role: 'assistant', messageKey: `answer-${i}`,
      text: Array.from({ length: 12 }, (_, j) => `ANSWER-${i}-${j} $x_${j}^2 + y^2$`).join('\n\n') }
  ]).flat();
  await setClaudeSession(session('long-history', longHistory));
  const initialMath = document.querySelectorAll('mjx-container').length;
  check(initialMath < 360, `offscreen history retains ${initialMath} formulas (1440 total)`);
  check(document.querySelectorAll('section.turn').length === 120, 'every historical turn must remain reachable');
  for (const index of [0, 60, 119, 0, 119]) {
    const target = document.querySelector(`[data-message-key="answer-${index}"]`);
    target.scrollIntoView({ block: 'start' });
    await until(() => target.querySelectorAll('mjx-container').length === 12,
      `scrolling to answer ${index} must restore every formula automatically`);
    await pause(60);
    check(target.textContent.includes(`ANSWER-${index}-11`), 'scroll remount must preserve complete text');
    check(Array.from(MathJax.startup.document.math).length < 360, 'scrolling must release offscreen MathItems');
  }
  const firstAnswer = document.querySelector('[data-message-key="answer-0"]');
  check(firstAnswer.closest('.assistant-output').querySelector('button').dataset.copyText === longHistory[1].text,
    'copy must retain the complete source of an offscreen answer');
  firstAnswer.scrollIntoView();
  await until(() => firstAnswer.querySelectorAll('mjx-container').length === 12, 'selected answer must be mounted');
  const range = document.createRange();
  range.selectNodeContents(firstAnswer);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  const selectedText = selection.toString();
  document.querySelector('[data-message-key="answer-119"]').scrollIntoView();
  await pause(100);
  check(selection.toString() === selectedText, 'scrolling must preserve text selected for quoting');
  check(firstAnswer.querySelectorAll('mjx-container').length === 12, 'selected content must remain mounted');
  selection.removeAllRanges();
  await until(() => !firstAnswer.childNodes.length, 'clearing selection must release offscreen content');
  await appendClaudeMessages({ sessionId: 'long-history' }, [{ role: 'assistant', text: 'LIVE-APPEND $z^3$' }]);
  window.scrollTo(0, document.body.scrollHeight);
  await until(() => Array.from(document.querySelectorAll('.assistant-text')).some(node =>
    node.textContent.includes('LIVE-APPEND') && node.querySelector('mjx-container')),
  'new visible formula must compile without manual sync');

  // A single small upward movement must escape bottom-follow immediately.
  // Exercise actual WKWebView scroll events, not just the anchor helpers.
  const scrollFailures = [];
  const checkScroll = (ok, message) => { if (!ok) scrollFailures.push(message); };
  const settleViewport = async () => {
    await pause(60);
    await PrettyTermRenderer.typeset([]);
    await pause(60);
  };
  const goBottom = async () => {
    window.scrollTo(0, document.body.scrollHeight);
    await settleViewport();
  };
  await goBottom();
  for (const distance of [4, 40, 40]) {
    const before = window.scrollY;
    window.scrollBy(0, -distance);
    await settleViewport();
    checkScroll(Math.abs(window.scrollY - (before - distance)) < 2,
      `upward ${distance}px was pulled back: ${before} -> ${window.scrollY}`);
  }

  // Delay completion AFTER real MathJax work to make the interaction race
  // deterministic without replacing formula rendering or browser geometry.
  const holdTypesetting = () => {
    const original = MathJax.typesetPromise;
    let release, entered;
    const started = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    MathJax.typesetPromise = async (...args) => {
      await original.apply(MathJax, args);
      entered();
      await gate;
    };
    return { started, finish() { MathJax.typesetPromise = original; release(); } };
  };
  for (const operation of ['typeset', 'append', 'replace']) {
    await goBottom();
    const held = holdTypesetting();
    const task = operation === 'typeset' ? PrettyTermRenderer.typeset([content])
      : operation === 'append' ? appendClaudeMessages({ sessionId: 'long-history' }, [formula])
      : setClaudeSession(session('long-history', longHistory));
    await held.started;
    window.scrollBy(0, -300);
    const chosenPosition = window.scrollY;
    held.finish();
    await task;
    checkScroll(Math.abs(window.scrollY - chosenPosition) < 2,
      `${operation} completion overrode scrolling: ${chosenPosition} -> ${window.scrollY}`);
    await settleViewport();
  }
  await goBottom();
  const held = holdTypesetting();
  const rendering = PrettyTermRenderer.typeset([content]);
  await held.started;
  const queuedAppend = appendClaudeMessages({ sessionId: 'long-history' }, [formula]);
  window.scrollBy(0, -40);
  const chosenPosition = window.scrollY;
  held.finish();
  await Promise.all([rendering, queuedAppend]);
  await settleViewport();
  checkScroll(Math.abs(window.scrollY - chosenPosition) < 2,
    `queued append overrode scrolling: ${chosenPosition} -> ${window.scrollY}`);
  await goBottom();
  await appendClaudeMessages({ sessionId: 'long-history' }, [formula]);
  await settleViewport();
  checkScroll(document.body.scrollHeight - innerHeight - scrollY < 2,
    'new output must still follow when the reader stays at the bottom');
  check(!scrollFailures.length, scrollFailures.join('\n'));

  await setClaudeSession(session('collapsed', [
    { role: 'user', text: 'tool test' },
    { kind: 'tool', toolName: 'Read', text: 'HIDDEN-FIRST $a^2$\n\n' + 'body\n'.repeat(300) + 'HIDDEN-LAST' },
    { kind: 'diff', filePath: '/tmp/complete.txt', oldText: '', newText: 'line\n'.repeat(300) + 'DIFF-LAST' }
  ]));
  const tool = document.querySelector('.tool-event');
  const diff = document.querySelector('.diff-event');
  check(tool.querySelector('.event-body').childNodes.length === 0, 'collapsed tool body must not be built');
  check(diff.querySelector('.diff-view').childNodes.length === 0, 'collapsed diff body must not be built');
  document.querySelector('.tool-group').open = true;
  tool.open = true;
  tool.scrollIntoView();
  await until(() => tool.querySelector('mjx-container'), 'expanding tool must compile its formula');
  check(tool.textContent.includes('HIDDEN-LAST'), 'expanded tool output must be complete');
  tool.open = false;
  await until(() => tool.querySelector('.event-body').childNodes.length === 0, 'closing tool must release its body');
  diff.open = true;
  diff.scrollIntoView();
  await until(() => diff.textContent.includes('DIFF-LAST'), 'expanding diff must show every line');
  check(diff.querySelectorAll('.diff-line.add').length === 301, 'expanded diff must have all 301 added lines');
  return { replacements: 20, retained, rapidFormulas: 2, historicalSummaryPreserved: true,
    historyFormulas: 1440, initialResidentFormulas: initialMath, scrollRemounts: 5,
    scrollInteractionCases: 8, collapsedBodies: 'released' };
})().then(result => { window.__ptMemoryResult = { ok: true, ...result }; },
  error => { window.__ptMemoryResult = { ok: false, error: String(error) + '\n' + (error.stack || '') }; });
