(function (scope, factory) {
  const api = factory(scope);
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (scope) {
    scope.PrettyTermRenderer = api;
    scope.setClaudeSession = api.setClaudeSession;
    scope.appendClaudeMessages = api.appendClaudeMessages;
    scope.__ptSessionMatches = api.sessionMatches;
    scope.setPrettyTermLanguage = api.setPrettyTermLanguage;
    scope.setClaudeWaiting = api.setClaudeWaiting;
    scope.setClaudeStream = api.setClaudeStream;
  }
})(typeof window !== 'undefined' ? window : globalThis, function (scope) {
  'use strict';

  const state = {
    session: null,
    renderedCount: 0,
    pendingQuote: null,
    language: 'zh-Hans',
    viewportAnchor: null,
    viewportCaptureFrame: 0,
    viewportRestoreFrame: 0,
    restoringViewport: false,
    viewportResizePending: false,
    typesetQueue: Promise.resolve(),
    renderedTurns: [],
    waiting: false,
    stream: null,
    streamFrame: 0
  };
  const editStats = new WeakMap();
  const virtualBodies = new Map();
  let liveRendering = false;
  let nextBodyID = 0;
  let virtualUpdateTimer = null;

  function renderLive(render) {
    liveRendering = true;
    try { return render(); }
    finally { liveRendering = false; }
  }

  // Keep source text for every message; only the expensive rendered body has a
  // viewport lifetime. The lightweight shell also preserves scroll reachability.
  function contentBody(className, text, render, attributes = '') {
    if (!liveRendering) return `<div class="${className}"${attributes}>${render()}</div>`;
    const id = String(++nextBodyID);
    const columns = Math.max(1, Math.floor(((scope.innerWidth || 720) - 100) / 8));
    const lines = String(text).split('\n').reduce((total, line) => total + Math.max(1, Math.ceil(line.length / columns)), 0);
    const height = Math.max(24, lines * 24);
    virtualBodies.set(id, { render, mounted: false, height });
    return `<div class="${className}"${attributes} data-virtual-body="${id}" style="min-height:${height}px;display:flow-root;box-sizing:border-box"></div>`;
  }

  function updateVirtualBodies(mathJax) {
    const root = rootElement();
    if (!root) return [];
    const added = [];
    const margin = scope.innerHeight;
    const selection = scope.getSelection();
    const nodes = Array.from(root.querySelectorAll('[data-virtual-body]'));
    // Read geometry before changing it, so removals never alternate reads and
    // writes and force a layout for each historical message.
    const changes = nodes.map(node => {
      const record = virtualBodies.get(node.dataset.virtualBody);
      const rect = node.getBoundingClientRect();
      const closed = Boolean(node.closest('details:not([open])'));
      const selected = record.mounted && selection && !selection.isCollapsed && selection.containsNode(node, true);
      return { node, record, rect, wanted: selected || (!closed && rect.bottom >= -margin && rect.top <= scope.innerHeight + margin) };
    });
    for (const { node, record, rect, wanted } of changes) {
      if (wanted === record.mounted) continue;
      if (wanted) {
        node.style.minHeight = '';
        node.innerHTML = record.render();
        record.mounted = true;
        added.push(node);
      } else {
        if (rect.height) record.height = rect.height;
        if (mathJax) mathJax.typesetClear([node]);
        node.replaceChildren();
        node.style.minHeight = `${record.height}px`;
        record.mounted = false;
      }
    }
    return added;
  }

  function scheduleVirtualContent() {
    if (virtualUpdateTimer !== null) return;
    virtualUpdateTimer = scope.setTimeout(() => {
      virtualUpdateTimer = null;
      typeset([]);
    }, 0);
  }

  function installVirtualContent() {
    if (!scope || !scope.document || !scope.addEventListener) return;
    scope.addEventListener('scroll', scheduleVirtualContent, { passive: true });
    scope.addEventListener('resize', scheduleVirtualContent);
    scope.document.addEventListener('toggle', scheduleVirtualContent, true);
    scope.document.addEventListener('selectionchange', scheduleVirtualContent);
  }

  const strings = {
    'zh-Hans': {
      quote: '引用选中内容', expandInput: '展开输入', lines: '行', codeChange: '代码改动',
      copyOutput: '复制',
      jumpToBottom: '回到底部',
      attachedImage: '图片 {count} · 点击展开或收起',
      showMoreFiles: '再显示 {count} 个文件', editedFiles: '已编辑 {count} 个文件',
      review: '审阅', thinking: '思考过程', tool: '工具调用',
      toolActivity: '工具调用情况', toolCount: '{count} 次', error: '错误',
      empty: '这个会话还没有可显示的事件。', loading: '正在读取 Claude 的会话事件…',
      waitingTitle: 'Claude 正在组织思路', waitingDetail: '消息已提交，回复会在这里出现',
      compactingTitle: 'Claude 正在压缩上下文', compactingDetail: '正在整理会话历史，完成后显示压缩结果',
      askUserTitle: 'Claude 有个问题', askUserCustomPlaceholder: '没有符合的选项？在这里说明',
      askUserSubmit: '提交回答', askUserSent: '已发送', askUserAnswered: '已作答',
      askUserSingle: '单选', askUserMultiple: '可多选', askUserCustom: '补充说明'
    },
    en: {
      quote: 'Quote selection', expandInput: 'Expand input', lines: 'lines', codeChange: 'Code change',
      copyOutput: 'Copy',
      jumpToBottom: 'Jump to bottom',
      attachedImage: 'Image {count} · Click to expand or collapse',
      showMoreFiles: 'Show {count} more files', editedFiles: 'Edited {count} files',
      review: 'Review', thinking: 'Thinking', tool: 'Tool call',
      toolActivity: 'Tool activity', toolCount: '{count} calls', error: 'Error',
      empty: 'This conversation has no events to display yet.', loading: 'Reading Claude conversation events…',
      waitingTitle: 'Claude is working through it', waitingDetail: 'Message submitted; the response will appear here',
      compactingTitle: 'Claude is compacting context', compactingDetail: 'Summarizing conversation history; results follow when complete',
      askUserTitle: 'Claude has a question', askUserCustomPlaceholder: 'None of these fit? Say what you want here',
      askUserSubmit: 'Submit answers', askUserSent: 'Sent', askUserAnswered: 'Answered',
      askUserSingle: 'Choose one', askUserMultiple: 'Choose any', askUserCustom: 'Add a note'
    }
  };

  function t(key, replacements) {
    let value = (strings[state.language] || strings['zh-Hans'])[key] || key;
    Object.entries(replacements || {}).forEach(([name, replacement]) => {
      value = value.replace(`{${name}}`, String(replacement));
    });
    return value;
  }

  function applyDocumentLanguage() {
    if (!scope || !scope.document) return;
    if (scope.document.documentElement) {
      scope.document.documentElement.lang = state.language === 'en' ? 'en' : 'zh-Hans';
    }
    const quoteButton = scope.document.querySelector('#quote-menu button');
    if (quoteButton) quoteButton.innerHTML = `<span aria-hidden="true">↩</span>${escapeHTML(t('quote'))}`;
    const loading = scope.document.querySelector('[data-i18n="loading"]');
    if (loading) loading.textContent = t('loading');
  }

  function setPrettyTermLanguage(language) {
    state.language = String(language || '').toLowerCase().startsWith('en') ? 'en' : 'zh-Hans';
    if (state.session) state.session.interfaceLanguage = state.language;
    applyDocumentLanguage();
    if (state.session) {
      const root = rootElement();
      if (root) return setClaudeSession(state.session).then(() => state.language);
    }
    return state.language;
  }

  function escapeHTML(value) {
    return String(value == null ? '' : value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function cleanTranscriptText(value) {
    return String(value == null ? '' : value)
      .replace(/(?:\u001B|\u009B)[[\]()#;?]*(?:(?:(?:[a-zA-Z\d]*(?:;[-a-zA-Z\d/#&.:=?%@~_]+)*)?\u0007)|(?:(?:\d{1,4}(?:[;:]\d{0,4})*)?[\dA-PR-TZcf-nq-uy=><~]))/g, '')
      .replace(/<\/?(?:(?:local-command|command|system|ide|tool|task|function)[\w:.-]*|antml:[\w:.-]*|invoke|parameter)(?:\s+[^<>]*?)?\s*\/?>/gi, '')
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
      .replace(/[ \t]+\n/g, '\n')
      .trim();
  }

  function elementForNode(node) {
    if (!node) return null;
    return node.nodeType === 1 ? node : node.parentElement;
  }

  function quoteSelectionDetails(selection, session) {
    if (!selection || selection.collapsed || selection.rangeCount !== 1) return null;
    const range = selection.getRangeAt(0);
    const startElement = elementForNode(range.startContainer);
    const endElement = elementForNode(range.endContainer);
    const startMessage = startElement && typeof startElement.closest === 'function'
      ? startElement.closest('.assistant-text') : null;
    const endMessage = endElement && typeof endElement.closest === 'function'
      ? endElement.closest('.assistant-text') : null;
    if (!startMessage || startMessage !== endMessage) return null;

    const text = String(selection.toString() || '')
      .replace(/\r\n?/g, '\n')
      .trim();
    if (!text) return null;
    const sessionId = String(session && (session.sessionId || session.id) || '');
    if (!sessionId) return null;
    return { container: startMessage, payload: { text, sessionId } };
  }

  function quotePayloadFromSelection(selection, session) {
    const details = quoteSelectionDetails(selection, session);
    return details ? details.payload : null;
  }

  function hideQuoteMenu() {
    if (!scope || !scope.document) return;
    const menu = scope.document.getElementById('quote-menu');
    if (menu) menu.hidden = true;
    state.pendingQuote = null;
  }

  function installQuoteMenu() {
    if (!scope || !scope.document || scope.document.getElementById('quote-menu')) return;
    const menu = scope.document.createElement('div');
    menu.id = 'quote-menu';
    menu.className = 'quote-menu';
    menu.hidden = true;
    menu.setAttribute('role', 'menu');
    const button = scope.document.createElement('button');
    button.type = 'button';
    button.setAttribute('role', 'menuitem');
    button.innerHTML = `<span aria-hidden="true">↩</span>${escapeHTML(t('quote'))}`;
    button.addEventListener('click', () => {
      const bridge = scope.webkit && scope.webkit.messageHandlers &&
        scope.webkit.messageHandlers.quoteSelection;
      if (state.pendingQuote && bridge && typeof bridge.postMessage === 'function') {
        bridge.postMessage(state.pendingQuote);
      }
      hideQuoteMenu();
    });
    menu.appendChild(button);
    scope.document.body.appendChild(menu);

    scope.document.addEventListener('contextmenu', event => {
      const selection = typeof scope.getSelection === 'function' ? scope.getSelection() : null;
      const details = quoteSelectionDetails(selection, state.session);
      const target = elementForNode(event.target);
      const targetMessage = target && typeof target.closest === 'function'
        ? target.closest('.assistant-text') : null;
      if (!details || targetMessage !== details.container) {
        hideQuoteMenu();
        return;
      }
      event.preventDefault();
      state.pendingQuote = details.payload;
      menu.hidden = false;
      const margin = 8;
      const width = menu.offsetWidth || 174;
      const height = menu.offsetHeight || 38;
      menu.style.left = `${Math.max(margin, Math.min(event.clientX, scope.innerWidth - width - margin))}px`;
      menu.style.top = `${Math.max(margin, Math.min(event.clientY, scope.innerHeight - height - margin))}px`;
    });
    scope.document.addEventListener('mousedown', event => {
      if (!menu.hidden && !menu.contains(event.target)) hideQuoteMenu();
    });
    scope.document.addEventListener('keydown', event => {
      if (event.key === 'Escape') hideQuoteMenu();
    });
    scope.document.addEventListener('selectionchange', () => {
      if (!menu.hidden && !quoteSelectionDetails(scope.getSelection(), state.session)) hideQuoteMenu();
    });
    scope.addEventListener('scroll', hideQuoteMenu, true);
  }

  function inlineMarkup(value) {
    const tokens = [];
    const stash = html => {
      const marker = `\uE000${tokens.length}\uE001`;
      tokens.push(html);
      return marker;
    };
    let text = String(value == null ? '' : value);

    text = text.replace(/`([^`\n]+)`/g,
      (_, code) => stash(`<code>${escapeHTML(code)}</code>`));
    text = text.replace(/\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
      (_, label, href) => stash(`<a href="${escapeHTML(String(href).trim())}" target="_blank" rel="noopener noreferrer">${escapeHTML(label)}</a>`));
    text = text.replace(/(^|[^\\$])\$([^$\n]+?)\$(?!\$)/g,
      (whole, prefix, tex) => {
        if (!tex.trim() || tex.trim() !== tex) return whole;
        return prefix + stash(`<span class="inline-math">\\(${escapeHTML(tex)}\\)</span>`);
      });

    text = escapeHTML(text);
    text = text.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
    text = text.replace(/(^|[\s(])_([^_\n]+)_($|[\s).,，。])/g, '$1<em>$2</em>$3');
    return text.replace(/\uE000(\d+)\uE001/g,
      (_, index) => tokens[Number(index)] || '');
  }

  function tableCells(value) {
    const source = String(value == null ? '' : value).trim();
    if (!source.includes('|')) return null;
    const cells = [];
    let cell = '';
    let escaped = false;
    let inCode = false;
    for (const character of source) {
      if (escaped) {
        cell += character === '|' ? '|' : `\\${character}`;
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === '`') {
        inCode = !inCode;
        cell += character;
      } else if (character === '|' && !inCode) {
        cells.push(cell.trim());
        cell = '';
      } else {
        cell += character;
      }
    }
    if (escaped) cell += '\\';
    cells.push(cell.trim());
    if (!cells[0]) cells.shift();
    if (!cells[cells.length - 1]) cells.pop();
    return cells;
  }

  function isTableSeparator(cells) {
    return Array.isArray(cells) && cells.length > 0 &&
      cells.every(cell => /^:?-{3,}:?$/.test(cell));
  }

  function renderMarkdown(value) {
    const lines = cleanTranscriptText(value).replace(/\r\n?/g, '\n').split('\n');
    const html = [];
    let fence = null;
    let math = null;
    let list = null;
    let listItemOpen = false;
    let pendingListBlanks = 0;

    const closeList = () => {
      if (!list) return;
      if (listItemOpen) html.push('</li>');
      html.push(`</${list}>`);
      list = null;
      listItemOpen = false;
      pendingListBlanks = 0;
    };
    const addListItem = (type, text, start = 1) => {
      if (list !== type) {
        closeList();
        list = type;
        html.push(type === 'ol' && start !== 1 ? `<ol start="${start}">` : `<${type}>`);
      } else if (listItemOpen) {
        html.push('</li>');
      }
      pendingListBlanks = 0;
      html.push(`<li>${inlineMarkup(text)}`);
      listItemOpen = true;
    };

    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      const line = lines[lineIndex];
      const trimmed = line.trim();
      if (fence) {
        if (/^```/.test(trimmed)) {
          html.push(`<pre><code${fence.language ? ` class="language-${escapeHTML(fence.language)}"` : ''}>${escapeHTML(fence.lines.join('\n'))}</code></pre>`);
          fence = null;
        } else {
          fence.lines.push(line);
        }
        continue;
      }
      if (math) {
        if (trimmed === '$$' || trimmed === '\\]') {
          html.push(`<div class="math-block">\\[\n${escapeHTML(math.join('\n'))}\n\\]</div>`);
          math = null;
        } else {
          math.push(line);
        }
        continue;
      }
      const unordered = line.match(/^(\s*)[-*+]\s+(.+)$/);
      if (unordered) {
        addListItem('ul', unordered[2]);
        continue;
      }
      const ordered = line.match(/^(\s*)(\d+)[.)]\s+(.+)$/);
      if (ordered) {
        addListItem('ol', ordered[3], Number(ordered[2]));
        continue;
      }
      if (list && !trimmed) {
        pendingListBlanks++;
        continue;
      }
      if (list && /^\s+/.test(line)) {
        pendingListBlanks = 0;
        html.push(`<div class="list-continuation">${inlineMarkup(trimmed)}</div>`);
        continue;
      }
      if (list) {
        const blankCount = pendingListBlanks;
        closeList();
        for (let blank = 0; blank < blankCount; blank++) html.push('<div class="blank"></div>');
      }
      if (/^```/.test(trimmed)) {
        closeList();
        fence = { language: trimmed.slice(3).trim(), lines: [] };
        continue;
      }
      if (trimmed === '$$' || trimmed === '\\[') {
        closeList();
        math = [];
        continue;
      }
      const oneLineMath = trimmed.match(/^\$\$(.+)\$\$$/);
      if (oneLineMath) {
        closeList();
        html.push(`<div class="math-block">\\[${escapeHTML(oneLineMath[1])}\\]</div>`);
        continue;
      }
      const headerCells = tableCells(line);
      const separatorCells = lineIndex + 1 < lines.length
        ? tableCells(lines[lineIndex + 1])
        : null;
      if (headerCells && separatorCells &&
          headerCells.length === separatorCells.length &&
          isTableSeparator(separatorCells)) {
        closeList();
        const rows = [];
        lineIndex += 2;
        while (lineIndex < lines.length) {
          const cells = tableCells(lines[lineIndex]);
          if (!cells || cells.length !== headerCells.length || !lines[lineIndex].trim()) break;
          rows.push(cells);
          lineIndex++;
        }
        lineIndex--;
        const head = headerCells.map(cell => `<th>${inlineMarkup(cell)}</th>`).join('');
        const body = rows.map(cells =>
          `<tr>${cells.map(cell => `<td>${inlineMarkup(cell)}</td>`).join('')}</tr>`
        ).join('');
        html.push(`<div class="table-scroll"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`);
        continue;
      }
      closeList();
      if (/^###\s+/.test(line)) html.push(`<h3>${inlineMarkup(line.replace(/^###\s+/, ''))}</h3>`);
      else if (/^##\s+/.test(line)) html.push(`<h2>${inlineMarkup(line.replace(/^##\s+/, ''))}</h2>`);
      else if (/^#\s+/.test(line)) html.push(`<h1>${inlineMarkup(line.replace(/^#\s+/, ''))}</h1>`);
      else if (/^\s*>\s?/.test(line)) html.push(`<blockquote>${inlineMarkup(line.replace(/^\s*>\s?/, ''))}</blockquote>`);
      else if (!trimmed) html.push('<div class="blank"></div>');
      else html.push(`<p>${inlineMarkup(line)}</p>`);
    }

    closeList();
    if (fence) html.push(`<pre><code>${escapeHTML(fence.lines.join('\n'))}</code></pre>`);
    if (math) html.push(`<p>${inlineMarkup(`$$\n${math.join('\n')}`)}</p>`);
    return html.join('');
  }

  async function renderFilePreview(payload) {
    const document = payload && typeof payload === 'object' ? payload : {};
    const kind = document.kind === 'markdown' ? 'markdown' : 'source';
    const title = String(document.title || '');
    const path = String(document.path || '');
    const text = String(document.text == null ? '' : document.text);
    const header = `<header class="file-document-header"><h1>${escapeHTML(title)}</h1>` +
      `<div class="file-document-path">${escapeHTML(path)}</div></header>`;
    let body = '';
    if (kind === 'markdown') {
      body = `<div class="file-markdown-body">${renderMarkdown(text)}</div>`;
    } else {
      const lines = text.replace(/\r\n?/g, '\n').split('\n');
      body = `<div class="file-source-body">${lines.map((line, index) =>
        `<div class="source-line"><span class="line-number">${index + 1}</span><code>${escapeHTML(line)}</code></div>`
      ).join('')}</div>`;
    }
    const html = `<article class="file-document ${kind}-document">${header}${body}</article>`;
    const root = rootElement();
    if (!root) return html;
    await typeset([root], mathJax => {
      if (mathJax && typeof mathJax.typesetClear === 'function') mathJax.typesetClear([root]);
      virtualBodies.clear();
      state.viewportAnchor = null;
      root.innerHTML = html;
      scope.document.body.classList.add('file-preview-mode');
      scope.scrollTo(0, 0);
    });
    return html;
  }

  function diffLines(oldValue, newValue) {
    const before = String(oldValue || '').replace(/\r\n?/g, '\n').split('\n');
    const after = String(newValue || '').replace(/\r\n?/g, '\n').split('\n');
    const result = [];
    let prefix = 0;
    while (prefix < before.length && prefix < after.length && before[prefix] === after[prefix]) {
      result.push({ type: 'context', text: before[prefix++] });
    }
    let beforeEnd = before.length;
    let afterEnd = after.length;
    const suffix = [];
    while (beforeEnd > prefix && afterEnd > prefix &&
           before[beforeEnd - 1] === after[afterEnd - 1]) {
      suffix.push({ type: 'context', text: before[--beforeEnd] });
      afterEnd--;
    }
    suffix.reverse();
    const left = before.slice(prefix, beforeEnd);
    const right = after.slice(prefix, afterEnd);
    if (!left.length) return result.concat(right.map(text => ({ type: 'add', text })), suffix);
    if (!right.length) return result.concat(left.map(text => ({ type: 'remove', text })), suffix);

    const rightValues = new Set(right);
    if (!left.some(line => rightValues.has(line))) {
      return result.concat(
        left.map(text => ({ type: 'remove', text })),
        right.map(text => ({ type: 'add', text })),
        suffix
      );
    }

    // Hirschberg reconstructs an exact LCS with two reusable score rows.
    // Recursion retains indices only; no per-distance search history is stored.
    const forward = new Uint32Array(right.length + 1);
    const backward = new Uint32Array(right.length + 1);
    const middle = [];
    const emit = (type, text) => middle.push({ type, text });
    const solve = (a0, a1, b0, b1) => {
      while (a0 < a1 && b0 < b1 && left[a0] === right[b0]) {
        emit('context', left[a0++]);
        b0++;
      }
      let tail = 0;
      while (a0 < a1 && b0 < b1 && left[a1 - 1] === right[b1 - 1]) {
        a1--; b1--; tail++;
      }
      if (a0 === a1) {
        for (let j = b0; j < b1; j++) emit('add', right[j]);
      } else if (b0 === b1) {
        for (let i = a0; i < a1; i++) emit('remove', left[i]);
      } else if (a1 - a0 === 1) {
        let match = b0;
        while (match < b1 && right[match] !== left[a0]) match++;
        if (match === b1) emit('remove', left[a0]);
        for (let j = b0; j < b1; j++) emit(j === match ? 'context' : 'add', right[j]);
      } else {
        const mid = Math.floor((a0 + a1) / 2);
        const width = b1 - b0;
        forward.fill(0, 0, width + 1);
        backward.fill(0, 0, width + 1);
        for (let i = a0; i < mid; i++) {
          let diagonal = 0;
          for (let j = 1; j <= width; j++) {
            const previous = forward[j];
            forward[j] = left[i] === right[b0 + j - 1] ? diagonal + 1
              : Math.max(forward[j], forward[j - 1]);
            diagonal = previous;
          }
        }
        for (let i = a1 - 1; i >= mid; i--) {
          let diagonal = 0;
          for (let j = 1; j <= width; j++) {
            const previous = backward[j];
            backward[j] = left[i] === right[b1 - j] ? diagonal + 1
              : Math.max(backward[j], backward[j - 1]);
            diagonal = previous;
          }
        }
        let split = 0;
        let best = -1;
        for (let j = 0; j <= width; j++) {
          const score = forward[j] + backward[width - j];
          if (score > best) { best = score; split = j; }
        }
        solve(a0, mid, b0, b0 + split);
        solve(mid, a1, b0 + split, b1);
      }
      for (let i = 0; i < tail; i++) emit('context', left[a1 + i]);
    };
    solve(0, left.length, 0, right.length);
    return result.concat(middle, suffix);
  }

  function eventText(message) {
    const value = message && (
      message.text != null ? message.text
        : message.content != null ? message.content
          : message.output != null ? message.output
            : message.error != null ? message.error
              : ''
    );
    return cleanTranscriptText(typeof value === 'string' ? value : JSON.stringify(value, null, 2));
  }

  function eventKind(message) {
    const raw = String(message.kind || message.type || '').toLowerCase();
    if (raw === 'question') return 'question';
    if (raw === 'diff' || raw === 'edit' || raw === 'write') return 'diff';
    if (raw.includes('think') || raw === 'reasoning') return 'thinking';
    if (raw.includes('error') || message.isError || message.error) return 'error';
    if (raw.includes('tool') || message.role === 'tool' || message.toolName || message.name) return 'tool';
    return message.role === 'user' ? 'user' : 'text';
  }

  function longContent(html, text) {
    const lineCount = String(text || '').split('\n').length;
    if (lineCount <= 20) return html;
    return `<details class="long-content"><summary>${escapeHTML(t('expandInput'))} · ${lineCount} ${escapeHTML(t('lines'))}</summary><div class="long-content-body">${html}</div></details>`;
  }

  function renderDiff(message) {
    const path = cleanTranscriptText(message.filePath || message.path || t('codeChange'));
    const { added, removed } = changedFileSummary([message])[0];
    const body = () => diffLines(message.oldText, message.newText).map(line => {
      const mark = line.type === 'add' ? '+' : line.type === 'remove' ? '−' : ' ';
      return `<div class="diff-line ${line.type}"><span class="diff-mark">${mark}</span><code>${escapeHTML(line.text)}</code></div>`;
    }).join('');
    return `<details class="event diff-event"><summary><span class="event-icon">Δ</span><span>${escapeHTML(message.toolName || 'Edit')}</span><code class="event-path">${escapeHTML(path)}</code><span class="diff-stats"><b>+${added}</b><i>−${removed}</i></span></summary>${contentBody('diff-view', message.newText || message.oldText || '', body)}</details>`;
  }

  function renderQuestionCard(message) {
    const messageKey = escapeHTML(message.messageKey || '');
    if (message.answered) {
      return `<section class="question-card answered" data-tool-use-id="${escapeHTML(message.toolUseId || '')}"${messageKey ? ` data-message-key="${messageKey}"` : ''}><header class="question-card-header"><span class="question-spark" aria-hidden="true">✓</span><span class="question-card-title">${escapeHTML(t('askUserAnswered'))}</span></header><div class="question-answer-text">${renderMarkdown(message.answerText || '')}</div></section>`;
    }
    const toolUseId = escapeHTML(message.toolUseId || '');
    const questions = Array.isArray(message.questions) ? message.questions : [];
    const blocks = questions.map((question, index) => {
      const options = Array.isArray(question.options) ? question.options : [];
      const multi = Boolean(question.multiSelect);
      const questionText = String(question.question || '');
      const optionButtons = options.map((option, optionIndex) => {
        const label = String((option && option.label) || '');
        const description = option && option.description ? String(option.description) : '';
        return `<button type="button" class="question-option" data-label="${escapeHTML(label)}" aria-pressed="false"><span class="question-option-mark" aria-hidden="true">${optionIndex + 1}</span><span class="question-option-copy"><span class="question-option-label">${escapeHTML(label)}</span>${description ? `<span class="question-option-desc">${escapeHTML(description)}</span>` : ''}</span><span class="question-option-check" aria-hidden="true">✓</span></button>`;
      }).join('');
      return `<div class="question-block" data-question-index="${index}" data-multi="${multi ? '1' : '0'}" data-question-text="${escapeHTML(questionText)}"><div class="question-block-head">${question.header ? `<span class="question-header-badge">${escapeHTML(String(question.header))}</span>` : ''}<span class="question-mode">${escapeHTML(t(multi ? 'askUserMultiple' : 'askUserSingle'))}</span></div><p class="question-text">${escapeHTML(questionText)}</p><div class="question-options">${optionButtons}</div><label class="question-custom-wrap"><span class="question-custom-icon" aria-hidden="true">＋</span><span class="question-custom-label">${escapeHTML(t('askUserCustom'))}</span><input type="text" class="question-custom-input" placeholder="${escapeHTML(t('askUserCustomPlaceholder'))}"></label></div>`;
    }).join('');
    return `<section class="question-card"${messageKey ? ` data-message-key="${messageKey}"` : ''} data-tool-use-id="${toolUseId}"><header class="question-card-header"><span class="question-spark" aria-hidden="true">✦</span><span class="question-card-title">${escapeHTML(t('askUserTitle'))}</span><span class="question-live-dot" aria-hidden="true"></span></header><div class="question-list">${blocks}</div><div class="question-card-footer"><button type="button" class="question-submit"><span>${escapeHTML(t('askUserSubmit'))}</span><span class="question-submit-arrow" aria-hidden="true">↗</span></button></div></section>`;
  }

  function installQuestionCardBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      if (!target || typeof target.closest !== 'function') return;

      const option = target.closest('.question-option');
      if (option) {
        const block = option.closest('.question-block');
        if (!block || block.closest('.question-card.submitted')) return;
        if (block.dataset.multi !== '1') {
          block.querySelectorAll('.question-option.selected').forEach(node => {
            if (node !== option) {
              node.classList.remove('selected');
              node.setAttribute('aria-pressed', 'false');
            }
          });
        }
        option.classList.toggle('selected');
        option.setAttribute('aria-pressed', option.classList.contains('selected') ? 'true' : 'false');
        option.classList.remove('selection-pop');
        void option.offsetWidth;
        option.classList.add('selection-pop');
        return;
      }

      const submit = target.closest('.question-submit');
      if (!submit) return;
      const card = submit.closest('.question-card');
      if (!card || card.classList.contains('submitted')) return;
      const lines = [];
      const answers = {};
      card.querySelectorAll('.question-block').forEach(block => {
        const questionText = block.dataset.questionText || '';
        const custom = block.querySelector('.question-custom-input');
        const customValue = custom ? custom.value.trim() : '';
        const answer = customValue || Array.from(block.querySelectorAll('.question-option.selected'))
          .map(node => node.dataset.label || '').join('、');
        if (answer) { lines.push(`${questionText}：${answer}`); answers[questionText] = answer; }
      });
      if (!lines.length) {
        card.classList.remove('needs-answer');
        void card.offsetWidth;
        card.classList.add('needs-answer');
        return;
      }
      const bridge = scope.webkit && scope.webkit.messageHandlers && scope.webkit.messageHandlers.answerQuestion;
      if (bridge && typeof bridge.postMessage === 'function') {
        const sessionId = String(state.session && (state.session.sessionId || state.session.id) || '');
        bridge.postMessage({ toolUseId: card.dataset.toolUseId || '', answers, text: lines.join('\n'), sessionId });
      }
      card.classList.add('submitted');
      submit.disabled = true;
      submit.textContent = t('askUserSent');
    });
  }

  function changedFileSummary(messages) {
    const files = new Map();
    (Array.isArray(messages) ? messages : []).forEach(message => {
      if (eventKind(message || {}) !== 'diff') return;
      const path = cleanTranscriptText(message.filePath || message.path || t('codeChange'));
      let stats = editStats.get(message);
      if (!stats || stats.oldText !== message.oldText || stats.newText !== message.newText) {
        stats = { oldText: message.oldText, newText: message.newText, added: 0, removed: 0 };
        for (const line of diffLines(message.oldText, message.newText)) {
          if (line.type === 'add') stats.added++;
          if (line.type === 'remove') stats.removed++;
        }
        editStats.set(message, stats);
      }
      const { added, removed } = stats;
      const existing = files.get(path) || { path, added: 0, removed: 0 };
      existing.added += added;
      existing.removed += removed;
      files.set(path, existing);
    });
    return Array.from(files.values()).sort((a, b) => a.path.localeCompare(b.path));
  }

  function renderTurnEditSummary(messages, session, turnIndex) {
    const files = changedFileSummary(messages);
    if (!files.length) return '';
    const added = files.reduce((sum, file) => sum + file.added, 0);
    const removed = files.reduce((sum, file) => sum + file.removed, 0);
    const sessionId = String(session && (session.sessionId || session.id) || '');
    const fileRow = file => `<button type="button" class="edit-file open-transcript-file" data-session-id="${escapeHTML(sessionId)}" data-file-path="${escapeHTML(file.path)}"><code title="${escapeHTML(file.path)}">${escapeHTML(file.path.split('/').pop() || file.path)}</code><span><b>+${file.added}</b><i>−${file.removed}</i></span></button>`;
    const first = files.slice(0, 3).map(fileRow).join('');
    const remaining = files.slice(3);
    const more = remaining.length
      ? `<details class="edit-more"><summary>${escapeHTML(t('showMoreFiles', { count: remaining.length }))}</summary>${remaining.map(fileRow).join('')}</details>`
      : '';
    return `<section class="edit-summary" data-edit-summary><button type="button" class="open-local-review" data-session-id="${escapeHTML(sessionId)}" data-turn-index="${Number.isInteger(turnIndex) ? turnIndex : 0}"><span class="edit-summary-icon" aria-hidden="true">▣</span><span class="edit-summary-title"><strong>${escapeHTML(t('editedFiles', { count: files.length }))}</strong><span class="edit-total"><b>+${added}</b><i>−${removed}</i></span></span><span class="edit-review-label">${escapeHTML(t('review'))}</span></button><div class="edit-files">${first}${more}</div></section>`;
  }

  function messageTurns(messages) {
    const turns = [];
    let current = null;
    (Array.isArray(messages) ? messages : []).forEach(message => {
      if (eventKind(message) === 'user') {
        current = [];
        turns.push(current);
      } else {
        if (!current) {
          current = [];
          turns.push(current);
        }
        current.push(message);
      }
    });
    return turns;
  }

  function refreshTurnEditSummaries(root, session, dirtyTurns) {
    if (!root) return;
    dirtyTurns.forEach((index, turn) => {
      const existing = turn.querySelector(':scope > [data-edit-summary]');
      const html = renderTurnEditSummary(state.renderedTurns[index] || [], session, index);
      if (!html) {
        if (existing) existing.remove();
        return;
      }
      const template = scope.document.createElement('template');
      template.innerHTML = html;
      const replacement = template.content.firstElementChild;
      if (existing) existing.replaceWith(replacement);
      else turn.appendChild(replacement);
    });
  }

  function installGitReviewBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && typeof target.closest === 'function'
        ? target.closest('.open-local-review') : null;
      if (!button) return;
      const bridge = scope.webkit && scope.webkit.messageHandlers &&
        scope.webkit.messageHandlers.openTranscriptEditReview;
      if (!bridge || typeof bridge.postMessage !== 'function') return;
      bridge.postMessage({
        sessionId: button.dataset.sessionId || '',
        turnIndex: Number(button.dataset.turnIndex || 0)
      });
    });
  }

  function installTranscriptFileBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && typeof target.closest === 'function'
        ? target.closest('.open-transcript-file') : null;
      if (!button) return;
      const bridge = scope.webkit && scope.webkit.messageHandlers &&
        scope.webkit.messageHandlers.openTranscriptFile;
      if (!bridge || typeof bridge.postMessage !== 'function') return;
      bridge.postMessage({
        sessionId: button.dataset.sessionId || '',
        filePath: button.dataset.filePath || ''
      });
    });
  }

  function installAssistantCopyBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && typeof target.closest === 'function'
        ? target.closest('.assistant-copy-button') : null;
      if (!button) return;
      const bridge = scope.webkit && scope.webkit.messageHandlers &&
        scope.webkit.messageHandlers.copyAssistantOutput;
      if (!bridge || typeof bridge.postMessage !== 'function') return;
      bridge.postMessage({
        text: button.dataset.copyText || '',
        sessionId: String(state.session && (state.session.sessionId || state.session.id) || '')
      });
    });
  }

  function installMessageImageBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && typeof target.closest === 'function'
        ? target.closest('.message-image') : null;
      if (!button) return;
      const expanded = button.getAttribute('aria-expanded') !== 'true';
      button.setAttribute('aria-expanded', String(expanded));
      captureViewportAnchor();
    });
  }

  function renderEvent(message, session) {
    message = message || {};
    const kind = eventKind(message);
    const text = eventText(message);
    const messageKey = escapeHTML(message.messageKey || '');
    const anchorAttribute = ` data-message-key="${messageKey}"`;
    if (kind === 'diff') return renderDiff(message);
    if (kind === 'question') return renderQuestionCard(message);
    if (kind === 'thinking') {
      return `<details class="event thinking-event"${anchorAttribute}><summary><span class="event-icon">◌</span>${escapeHTML(t('thinking'))}</summary>${contentBody('event-body', text, () => renderMarkdown(text))}</details>`;
    }
    if (kind === 'tool') {
      const name = cleanTranscriptText(message.toolName || message.name || t('tool'));
      return `<details class="event tool-event"${anchorAttribute}><summary><span class="event-icon">›_</span>${escapeHTML(name)}</summary>${contentBody('event-body', text, () => renderMarkdown(text))}</details>`;
    }
    if (kind === 'error') {
      const name = cleanTranscriptText(message.title || message.toolName || t('error'));
      return `<details class="event error-event" open${anchorAttribute}><summary><span class="event-icon">!</span>${escapeHTML(name)}</summary>${contentBody('event-body', text, () => renderMarkdown(text))}</details>`;
    }
    if (kind === 'user') {
      const images = Array.isArray(message.images) ? message.images : [];
      if (images.length) {
        const pictures = images.map((src, index) => {
          const label = escapeHTML(t('attachedImage', { count: index + 1 }));
          return `<button type="button" class="message-image" aria-expanded="false" aria-label="${label}" title="${label}"><img src="${escapeHTML(src)}" alt="${label}" loading="lazy" decoding="async"></button>`;
        }).join('');
        const body = text ? contentBody('user-message-text', text,
          () => longContent(renderMarkdown(text), text)) : '';
        return `<div class="turn-prompt"${anchorAttribute}><div class="message-images">${pictures}</div>${body}</div>`;
      }
      if (liveRendering) {
        const lineCount = text.split('\n').length;
        if (lineCount > 20) return `<div class="turn-prompt"${anchorAttribute}><details class="long-content"><summary>${escapeHTML(t('expandInput'))} · ${lineCount} ${escapeHTML(t('lines'))}</summary>${contentBody('long-content-body', text, () => renderMarkdown(text))}</details></div>`;
        return contentBody('turn-prompt', text, () => renderMarkdown(text), anchorAttribute);
      }
      return `<div class="turn-prompt"${anchorAttribute}>${longContent(renderMarkdown(text), text)}</div>`;
    }
    const model = cleanTranscriptText(message.model || (session && session.model) || 'Claude');
    return `<section class="assistant-output"><div class="assistant-output-toolbar"><button type="button" class="assistant-copy-button" data-copy-text="${escapeHTML(text)}"><span aria-hidden="true">⧉</span>${escapeHTML(t('copyOutput'))}</button></div>${contentBody('assistant-text', text, () => renderMarkdown(text), ` data-model="${escapeHTML(model)}"${anchorAttribute}`)}</section>`;
  }

  function renderToolGroup(messages, session) {
    const tools = (Array.isArray(messages) ? messages : [])
      .filter(message => eventKind(message || {}) === 'tool');
    if (!tools.length) return '';
    const body = tools.map(message => renderEvent(message, session)).join('');
    return `<details class="tool-group" data-tool-count="${tools.length}"><summary><span class="event-icon">›_</span><span class="tool-group-title">${escapeHTML(t('toolActivity'))}</span><span class="tool-group-count">${escapeHTML(t('toolCount', { count: tools.length }))}</span></summary><div class="tool-group-events">${body}</div></details>`;
  }

  function renderEventSequence(messages, session) {
    const html = [];
    let toolRun = [];
    const flushTools = () => {
      if (!toolRun.length) return;
      html.push(renderToolGroup(toolRun, session));
      toolRun = [];
    };
    (Array.isArray(messages) ? messages : []).forEach(message => {
      if (eventKind(message || {}) === 'tool') {
        toolRun.push(message);
        return;
      }
      flushTools();
      html.push(renderEvent(message, session));
    });
    flushTools();
    return html.join('');
  }

  function renderClaudeWaiting() {
    return `<div class="claude-waiting" role="status" aria-live="polite">
      <div class="thought-route" aria-hidden="true">
        <span class="route-terminal">›_</span><span class="route-line"></span>
        <i class="thought-packet"></i><i class="thought-packet"></i><i class="thought-packet"></i>
        <span class="route-core">
          <svg class="claude-mark" viewBox="0 0 32 32" role="img" aria-label="Claude">
            <path d="M3 16h26M4.74 9.5l22.52 13M9.5 4.74l13 22.52M16 3v26M22.5 4.74l-13 22.52M27.26 9.5l-22.52 13" />
          </svg>
        </span>
      </div>
      <div class="waiting-copy"><strong>${escapeHTML(t(state.stream && state.stream.compacting ? 'compactingTitle' : 'waitingTitle'))}</strong><span>${escapeHTML(t(state.stream && state.stream.compacting ? 'compactingDetail' : 'waitingDetail'))}</span></div>
    </div>`;
  }

  function syncClaudeWaiting(root) {
    if (!root) return '';
    root.querySelectorAll('.claude-waiting').forEach(node => node.remove());
    const compacting = state.stream && state.stream.compacting;
    if (!compacting && (!state.waiting || (state.stream && state.stream.active && state.stream.messages.length))) return '';
    const template = scope.document.createElement('template');
    template.innerHTML = renderClaudeWaiting();
    root.appendChild(template.content);
    return renderClaudeWaiting();
  }

  function setClaudeWaiting(waiting) {
    state.waiting = Boolean(waiting);
    if (state.session) state.session.awaitingReply = state.waiting;
    const root = rootElement();
    if (!root) return state.waiting;
    const shouldFollow = nearBottom();
    syncClaudeWaiting(root);
    if (shouldFollow && typeof scope.scrollTo === 'function') {
      const reduce = scope.matchMedia && scope.matchMedia('(prefers-reduced-motion: reduce)').matches;
      scope.scrollTo({ top: scope.document.body.scrollHeight, behavior: reduce ? 'auto' : 'smooth' });
    }
    captureViewportAnchor();
    return state.waiting;
  }

  function renderSession(session) {
    session = session || {};
    if (session.interfaceLanguage) {
      state.language = String(session.interfaceLanguage).toLowerCase().startsWith('en') ? 'en' : 'zh-Hans';
    }
    applyDocumentLanguage();
    const messages = Array.isArray(session.messages) ? session.messages : [];
    if (!messages.length) {
      return `<div class="empty">${escapeHTML(t('empty'))}</div>`;
    }
    const turns = [];
    let current = null;
    const flush = () => {
      if (!current) return;
      turns.push(`<section class="turn">${current.prompt}<div class="turn-events">${renderEventSequence(current.events, session)}</div>${renderTurnEditSummary(current.events, session, turns.length)}</section>`);
    };

    messages.forEach(message => {
      if (eventKind(message) === 'user') {
        flush();
        current = {
          prompt: `<header class="turn-header"><span class="turn-label">TURN</span>${renderEvent(message, session)}</header>`,
          events: []
        };
      } else {
        if (!current) current = { prompt: '<header class="turn-header"><span class="turn-label">TURN</span></header>', events: [] };
        current.events.push(message);
      }
    });
    flush();
    return turns.join('') + (session.awaitingReply ? renderClaudeWaiting() : '');
  }

  function rootElement() {
    return scope && scope.document ? scope.document.getElementById('content') : null;
  }

  // Only the currently arriving blocks are mutable. Historical turns keep their
  // DOM, selection, expanded details and viewport position while tokens arrive.
  function applyQuestionUpdates(updates) {
    const answers = new Map((updates || []).filter(message => message.answered)
      .map(message => [message.toolUseId, message]));
    if (!answers.size) return;
    for (const message of (state.session && state.session.messages) || []) {
      const update = message.kind === 'question' && answers.get(message.toolUseId);
      if (update) Object.assign(message, { answered: true, answerText: update.answerText });
    }
    const root = rootElement();
    if (!root) return;
    root.querySelectorAll('.question-card').forEach(card => {
      const update = answers.get(card.dataset.toolUseId);
      if (!update) return;
      const signature = JSON.stringify([update.toolUseId, update.answerText]);
      if (card.dataset.answerSignature === signature) return;
      const template = scope.document.createElement('template');
      template.innerHTML = renderQuestionCard(update);
      const replacement = template.content.firstElementChild;
      replacement.dataset.answerSignature = signature;
      card.replaceWith(replacement);
    });
  }

  function renderClaudeStream() {
    const root = rootElement();
    if (!root) return;
    let region = root.querySelector(':scope > .claude-stream');
    if (!state.stream || !sessionMatches(state.stream)) {
      if (region) region.remove();
      return;
    }
    applyQuestionUpdates(state.stream.questionUpdates);
    const persisted = new Set((state.session.messages || []).map(message => message.messageKey));
    const messages = state.stream.messages.filter(message => !persisted.has(message.messageKey));
    const shouldFollow = nearBottom();
    captureViewportAnchor();
    if (!region && messages.length) {
      region = scope.document.createElement('div');
      region.className = 'claude-stream';
    }
    if (region) {
      const existing = new Map(Array.from(region.children).map(node => [node.dataset.streamId, node]));
      const retained = new Set();
      messages.forEach((message, index) => {
        const identity = message.streamID || message.messageKey;
        retained.add(identity);
        let node = existing.get(identity);
        if (!node) {
          node = scope.document.createElement('div');
          node.dataset.streamId = identity;
        }
        const signature = JSON.stringify(message);
        if (node.__streamSignature !== signature) {
          const details = Array.from(node.querySelectorAll('details')).map(item => item.open);
          const mathJax = scope.MathJax;
          if (mathJax && mathJax.typesetClear) mathJax.typesetClear([node]);
          node.innerHTML = renderEvent(message, state.session);
          node.querySelectorAll('details').forEach((item, index) => {
            if (index < details.length) item.open = details[index];
          });
          node.classList.toggle('streaming-block', Boolean(message.streaming));
          node.__streamSignature = signature;
          if (!message.streaming) typeset([node]);
        }
        if (region.children[index] !== node)
          region.insertBefore(node, region.children[index] || null);
      });
      existing.forEach((node, identity) => { if (!retained.has(identity)) node.remove(); });
      if (messages.length) {
        const waiting = root.querySelector(':scope > .claude-waiting');
        if (region.parentNode !== root || region.nextSibling !== waiting)
          root.insertBefore(region, waiting);
      }
      else region.remove();
    }
    syncClaudeWaiting(root);
    if (shouldFollow) scope.scrollTo(0, scope.document.body.scrollHeight);
    else restoreViewportAnchor();
    captureViewportAnchor();
  }

  function setClaudeStream(snapshot) {
    if (!sessionMatches(snapshot)) return false;
    if (state.stream && state.stream.sessionId === snapshot.sessionId &&
        Number(state.stream.revision) > Number(snapshot.revision)) return false;
    state.stream = Object.assign({}, snapshot, {
      messages: Array.isArray(snapshot.messages) ? snapshot.messages : []
    });
    if (!state.streamFrame) {
      state.streamFrame = scope.requestAnimationFrame(() => {
        state.streamFrame = 0;
        renderClaudeStream();
      });
    }
    return true;
  }

  function nearBottom() {
    if (!scope || !scope.document) return true;
    // Only rounding at the actual bottom counts as following. A reading
    // position just above it must not be snapped back by a scroll refresh.
    return scope.document.body.scrollHeight - scope.scrollY - scope.innerHeight < 1;
  }

  function viewportRangeAtPoint(x, y) {
    if (!scope || !scope.document) return null;
    if (typeof scope.document.caretRangeFromPoint === 'function') {
      return scope.document.caretRangeFromPoint(x, y);
    }
    if (typeof scope.document.caretPositionFromPoint === 'function') {
      const position = scope.document.caretPositionFromPoint(x, y);
      if (!position) return null;
      const range = scope.document.createRange();
      range.setStart(position.offsetNode, position.offset);
      range.collapse(true);
      return range;
    }
    return null;
  }

  function measurableRange(node, offset) {
    if (!node || !node.isConnected || !scope || !scope.document) return null;
    const range = scope.document.createRange();
    try {
      if (node.nodeType === 3 && node.length > 0) {
        const safeOffset = Math.max(0, Math.min(Number(offset) || 0, node.length));
        const start = safeOffset < node.length ? safeOffset : Math.max(0, safeOffset - 1);
        range.setStart(node, start);
        range.setEnd(node, Math.min(node.length, start + 1));
      } else {
        range.selectNode(node.nodeType === 1 ? node : node.parentElement);
      }
    } catch (_) {
      return null;
    }
    return range;
  }

  function captureViewportAnchor() {
    if (!scope || !scope.document || state.restoringViewport) return null;
    if (nearBottom()) {
      state.viewportAnchor = { followBottom: true };
      return state.viewportAnchor;
    }
    const root = rootElement();
    const rootRect = root && root.getBoundingClientRect ? root.getBoundingClientRect() : null;
    const x = rootRect
      ? Math.max(8, Math.min(scope.innerWidth - 8, rootRect.left + Math.min(48, rootRect.width / 3)))
      : Math.max(8, Math.min(scope.innerWidth - 8, 32));
    const samplePoints = [8, 24, 48, Math.min(scope.innerHeight - 8, 96)];
    for (const y of samplePoints) {
      const range = viewportRangeAtPoint(x, y);
      if (!range || !range.startContainer) continue;
      const measurable = measurableRange(range.startContainer, range.startOffset);
      const rect = measurable && measurable.getBoundingClientRect();
      if (!rect || !Number.isFinite(rect.top)) continue;
      state.viewportAnchor = {
        followBottom: false,
        node: range.startContainer,
        offset: range.startOffset,
        top: rect.top
      };
      return state.viewportAnchor;
    }
    const element = scope.document.elementFromPoint(x, Math.min(scope.innerHeight - 8, 24));
    const block = element && typeof element.closest === 'function'
      ? element.closest('[data-message-key], .edit-summary, section.turn') : null;
    if (block) {
      state.viewportAnchor = {
        followBottom: false,
        element: block,
        top: block.getBoundingClientRect().top
      };
    }
    return state.viewportAnchor;
  }

  function restoreViewportAnchor() {
    if (!scope || !scope.document || !state.viewportAnchor) return false;
    const anchor = state.viewportAnchor;
    state.restoringViewport = true;
    if (anchor.followBottom) {
      scope.scrollTo({ top: scope.document.body.scrollHeight, behavior: 'auto' });
    } else {
      let top = null;
      const range = measurableRange(anchor.node, anchor.offset);
      const rect = range && range.getBoundingClientRect();
      if (rect && Number.isFinite(rect.top)) top = rect.top;
      else if (anchor.element && anchor.element.isConnected) {
        top = anchor.element.getBoundingClientRect().top;
      }
      if (Number.isFinite(top)) scope.scrollBy(0, top - anchor.top);
    }
    const finish = () => {
      state.restoringViewport = false;
      state.viewportResizePending = false;
      captureViewportAnchor();
    };
    if (typeof scope.requestAnimationFrame === 'function') scope.requestAnimationFrame(finish);
    else finish();
    return true;
  }

  function installJumpToBottom() {
    if (!scope || !scope.document) return;
    const button = scope.document.getElementById('jump-to-bottom');
    if (!button) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      button.hidden = !state.session || nearBottom();
      button.title = t('jumpToBottom');
      button.setAttribute('aria-label', t('jumpToBottom'));
    };
    const schedule = () => {
      if (!frame) frame = scope.requestAnimationFrame(update);
    };
    button.addEventListener('click', () => {
      state.viewportAnchor = { followBottom: true };
      scope.scrollTo({ top: scope.document.body.scrollHeight, behavior: 'auto' });
      captureViewportAnchor();
      scheduleVirtualContent();
      schedule();
    });
    scope.addEventListener('scroll', schedule, { passive: true });
    scope.addEventListener('resize', schedule);
    const observer = new scope.ResizeObserver(schedule);
    observer.observe(scope.document.body);
    observer.observe(rootElement());
    update();
  }

  function installStableViewport() {
    if (!scope || !scope.document || typeof scope.addEventListener !== 'function') return;
    const scheduleCapture = () => {
      if (state.restoringViewport || state.viewportResizePending) return;
      if (state.viewportCaptureFrame && typeof scope.cancelAnimationFrame === 'function') {
        scope.cancelAnimationFrame(state.viewportCaptureFrame);
      }
      const capture = () => {
        state.viewportCaptureFrame = 0;
        captureViewportAnchor();
      };
      state.viewportCaptureFrame = typeof scope.requestAnimationFrame === 'function'
        ? scope.requestAnimationFrame(capture) : (capture(), 0);
    };
    scope.addEventListener('scroll', scheduleCapture, { passive: true });
    scope.addEventListener('resize', () => {
      state.viewportResizePending = true;
      if (state.viewportCaptureFrame && typeof scope.cancelAnimationFrame === 'function') {
        scope.cancelAnimationFrame(state.viewportCaptureFrame);
        state.viewportCaptureFrame = 0;
      }
      if (state.viewportRestoreFrame && typeof scope.cancelAnimationFrame === 'function') {
        scope.cancelAnimationFrame(state.viewportRestoreFrame);
      }
      const restore = () => {
        state.viewportRestoreFrame = 0;
        restoreViewportAnchor();
      };
      state.viewportRestoreFrame = typeof scope.requestAnimationFrame === 'function'
        ? scope.requestAnimationFrame(restore) : (restore(), 0);
    });
    scheduleCapture();
  }

  function typeset(targets, updateDOM) {
    state.typesetQueue = state.typesetQueue.then(async () => {
      const mathJax = scope && scope.MathJax;
      if (mathJax && mathJax.startup && mathJax.startup.promise) {
        await mathJax.startup.promise;
      }
      if (updateDOM) updateDOM(mathJax);
      const followBottom = rootElement() && nearBottom();
      const anchor = rootElement() && (captureViewportAnchor() || state.viewportAnchor);
      const mounted = updateVirtualBodies(mathJax);
      if (!mathJax || typeof mathJax.typesetPromise !== 'function') return;
      const requestedTargets = Array.from(new Set([...Array.from(typeof targets === 'function' ? targets() : targets || []), ...mounted]));
      const connectedTargets = requestedTargets.filter(target =>
        target && (typeof target.isConnected !== 'boolean' || target.isConnected) &&
        !requestedTargets.some(parent => parent !== target && parent.contains(target)));
      const scrollBeforeTypeset = scope.scrollY;
      if (connectedTargets.length) await mathJax.typesetPromise(connectedTargets);
      // The captured anchor belongs to the viewport before the asynchronous
      // work. If it has moved meanwhile, leave the newer position alone.
      if (scope.scrollY !== scrollBeforeTypeset) return;
      if (followBottom) scope.scrollTo(0, scope.document.body.scrollHeight);
      else if (anchor) {
        const range = measurableRange(anchor.node, anchor.offset);
        const rect = range ? range.getBoundingClientRect()
          : anchor.element && anchor.element.isConnected && anchor.element.getBoundingClientRect();
        if (rect) scope.scrollBy(0, rect.top - anchor.top);
      }
    }).catch(error => {
      if (scope && scope.console) scope.console.error(error);
    });
    return state.typesetQueue;
  }

  async function setClaudeSession(session) {
    const root = rootElement();
    if (!sessionMatches(session)) state.stream = null;
    state.session = Object.assign({}, session, {
      messages: Array.isArray(session && session.messages) ? session.messages.slice() : []
    });
    state.waiting = Boolean(state.session.awaitingReply);
    state.renderedCount = state.session.messages.length;
    if (!root) return renderSession(state.session);
    const snapshot = state.session;
    await typeset([root], mathJax => {
      const shouldFollow = nearBottom();
      if (mathJax && typeof mathJax.typesetClear === 'function') mathJax.typesetClear([root]);
      state.viewportAnchor = null;
      state.pendingQuote = null;
      virtualBodies.clear();
      state.renderedTurns = messageTurns(snapshot.messages);
      root.innerHTML = renderLive(() => renderSession(snapshot));
      renderClaudeStream();
      if (shouldFollow) scope.scrollTo(0, scope.document.body.scrollHeight);
    });
    captureViewportAnchor();
    return state.renderedCount;
  }

  // 原生侧追加时只发元数据；会话标识一致才合并增量。
  function sessionMatches(session) {
    if (!state.session || !session) return false;
    const mine = state.session.sessionId || '';
    const theirs = session.sessionId || '';
    return mine.length > 0 && mine === theirs;
  }

  async function appendClaudeMessages(session, newMessages) {
    const incoming = Array.isArray(newMessages) ? newMessages : [];
    if (!sessionMatches(session)) {
      return null;
    }
    const metadata = Object.assign({}, session);
    delete metadata.messages;
    state.session = Object.assign({}, state.session, metadata, {
      messages: state.session.messages.concat(incoming)
    });
    state.waiting = Boolean(state.session.awaitingReply);
    state.renderedCount = state.session.messages.length;
    const root = rootElement();
    if (!root) return renderSession(state.session);
    applyQuestionUpdates(session.questionUpdates);
    if (!incoming.length) return state.renderedCount;

    const snapshot = state.session;
    const addedNodes = [];
    await typeset(() => addedNodes, () => {
      const shouldFollow = nearBottom();
      root.querySelectorAll('.claude-waiting').forEach(node => node.remove());
      const dirtyTurns = new Map();
      const appendHTML = (parent, html) => {
        const template = scope.document.createElement('template');
        template.innerHTML = html;
        const nodes = Array.from(template.content.childNodes);
        nodes.forEach(node => parent.appendChild(node));
        addedNodes.push(...nodes.filter(node => node.nodeType === 1));
        return nodes.find(node => node.nodeType === 1) || null;
      };
      const emptyTurn = () => appendHTML(root,
        '<section class="turn"><header class="turn-header"><span class="turn-label">TURN</span></header><div class="turn-events"></div></section>');
      const appendToolMessage = (events, message) => {
        const previous = events.lastElementChild;
        if (!previous || !previous.classList.contains('tool-group')) {
          appendHTML(events, renderLive(() => renderToolGroup([message], snapshot)));
          return;
        }
        const toolEvents = previous.querySelector(':scope > .tool-group-events');
        appendHTML(toolEvents, renderLive(() => renderEvent(message, snapshot)));
        const count = Number(previous.dataset.toolCount || 0) + 1;
        previous.dataset.toolCount = String(count);
        const countLabel = previous.querySelector(':scope > summary .tool-group-count');
        if (countLabel) countLabel.textContent = t('toolCount', { count });
      };

      incoming.forEach(message => {
        if (eventKind(message) === 'user') {
          state.renderedTurns.push([]);
          appendHTML(root,
            `<section class="turn"><header class="turn-header"><span class="turn-label">TURN</span>${renderLive(() => renderEvent(message, snapshot))}</header><div class="turn-events"></div></section>`);
          return;
        }
        let turn = root.querySelector('section.turn:last-of-type');
        if (!turn) {
          turn = emptyTurn();
          state.renderedTurns.push([]);
        }
        const turnIndex = state.renderedTurns.length - 1;
        state.renderedTurns[turnIndex].push(message);
        if (eventKind(message) === 'diff') dirtyTurns.set(turn, turnIndex);
        const events = turn.querySelector('.turn-events');
        if (eventKind(message) === 'tool') appendToolMessage(events, message);
        else appendHTML(events, renderLive(() => renderEvent(message, snapshot)));
      });
      refreshTurnEditSummaries(root, snapshot, dirtyTurns);
      renderClaudeStream();
      syncClaudeWaiting(root);
      if (shouldFollow) scope.scrollTo(0, scope.document.body.scrollHeight);
    });
    captureViewportAnchor();
    return state.renderedCount;
  }

  installQuoteMenu();
  installGitReviewBridge();
  installTranscriptFileBridge();
  installAssistantCopyBridge();
  installMessageImageBridge();
  installQuestionCardBridge();
  installStableViewport();
  installJumpToBottom();
  installVirtualContent();

  return {
    cleanTranscriptText,
    inlineMarkup,
    renderMarkdown,
    renderFilePreview,
    diffLines,
    changedFileSummary,
    renderTurnEditSummary,
    captureViewportAnchor,
    restoreViewportAnchor,
    renderEvent,
    renderSession,
    quotePayloadFromSelection,
    renderClaudeWaiting,
    setPrettyTermLanguage,
    setClaudeWaiting,
    setClaudeStream,
    typeset,
    setClaudeSession,
    appendClaudeMessages,
    sessionMatches
  };
});
