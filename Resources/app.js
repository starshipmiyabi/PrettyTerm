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
    waiting: false
  };

  const MAX_QUOTE_LENGTH = 20000;

  const strings = {
    'zh-Hans': {
      quote: '引用选中内容', expandInput: '展开输入', lines: '行', codeChange: '代码改动',
      showMoreFiles: '再显示 {count} 个文件', editedFiles: '已编辑 {count} 个文件',
      review: '审阅', thinking: '思考过程', tool: '工具调用', error: '错误',
      empty: '这个会话还没有可显示的事件。', loading: '正在读取 Claude 的会话事件…',
      waitingTitle: 'Claude 正在组织思路', waitingDetail: 'Terminal 信号已送达，回复会在这里出现'
    },
    en: {
      quote: 'Quote selection', expandInput: 'Expand input', lines: 'lines', codeChange: 'Code change',
      showMoreFiles: 'Show {count} more files', editedFiles: 'Edited {count} files',
      review: 'Review', thinking: 'Thinking', tool: 'Tool call', error: 'Error',
      empty: 'This conversation has no events to display yet.', loading: 'Reading Claude conversation events…',
      waitingTitle: 'Claude is working through it', waitingDetail: 'Terminal signal delivered; the response will appear here'
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
      if (root) root.innerHTML = renderSession(state.session);
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
    if (!text || text.length > MAX_QUOTE_LENGTH) return null;
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

  function safeHref(value) {
    const href = String(value || '').trim();
    return /^(?:https?:|mailto:)/i.test(href) ? href : '';
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
      (_, label, href) => {
        const safe = safeHref(href);
        return safe
          ? stash(`<a href="${escapeHTML(safe)}" target="_blank" rel="noopener noreferrer">${escapeHTML(label)}</a>`)
          : escapeHTML(label);
      });
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

  function diffLines(oldValue, newValue) {
    const before = String(oldValue || '').replace(/\r\n?/g, '\n').split('\n');
    const after = String(newValue || '').replace(/\r\n?/g, '\n').split('\n');
    if (before.length * after.length > 120000) {
      return before.map(text => ({ type: 'remove', text }))
        .concat(after.map(text => ({ type: 'add', text })));
    }
    const table = Array.from({ length: before.length + 1 },
      () => new Uint32Array(after.length + 1));
    for (let i = before.length - 1; i >= 0; i--) {
      for (let j = after.length - 1; j >= 0; j--) {
        table[i][j] = before[i] === after[j]
          ? table[i + 1][j + 1] + 1
          : Math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    const result = [];
    let i = 0;
    let j = 0;
    while (i < before.length || j < after.length) {
      if (i < before.length && j < after.length && before[i] === after[j]) {
        result.push({ type: 'context', text: before[i++] });
        j++;
      } else if (i < before.length && (j >= after.length || table[i + 1][j] >= table[i][j + 1])) {
        result.push({ type: 'remove', text: before[i++] });
      } else {
        result.push({ type: 'add', text: after[j++] });
      }
    }
    return result;
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
    const lines = diffLines(message.oldText, message.newText);
    const added = lines.filter(line => line.type === 'add').length;
    const removed = lines.filter(line => line.type === 'remove').length;
    const body = lines.map(line => {
      const mark = line.type === 'add' ? '+' : line.type === 'remove' ? '−' : ' ';
      return `<div class="diff-line ${line.type}"><span class="diff-mark">${mark}</span><code>${escapeHTML(line.text)}</code></div>`;
    }).join('');
    return `<details class="event diff-event"><summary><span class="event-icon">Δ</span><span>${escapeHTML(message.toolName || 'Edit')}</span><code class="event-path">${escapeHTML(path)}</code><span class="diff-stats"><b>+${added}</b><i>−${removed}</i></span></summary><div class="diff-view">${body}</div></details>`;
  }

  function changedFileSummary(messages) {
    const files = new Map();
    (Array.isArray(messages) ? messages : []).forEach(message => {
      if (eventKind(message || {}) !== 'diff') return;
      const path = cleanTranscriptText(message.filePath || message.path || t('codeChange'));
      const lines = diffLines(message.oldText, message.newText);
      const added = lines.filter(line => line.type === 'add').length;
      const removed = lines.filter(line => line.type === 'remove').length;
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
    const fileRow = file => `<div class="edit-file"><code title="${escapeHTML(file.path)}">${escapeHTML(file.path.split('/').pop() || file.path)}</code><span><b>+${file.added}</b><i>−${file.removed}</i></span></div>`;
    const first = files.slice(0, 3).map(fileRow).join('');
    const remaining = files.slice(3);
    const more = remaining.length
      ? `<details class="edit-more"><summary>${escapeHTML(t('showMoreFiles', { count: remaining.length }))}</summary>${remaining.map(fileRow).join('')}</details>`
      : '';
    const sessionId = String(session && (session.sessionId || session.id) || '');
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

  function refreshTurnEditSummaries(root, session) {
    if (!root) return;
    const turns = messageTurns(session && session.messages);
    const nodes = Array.from(root.querySelectorAll('section.turn'));
    nodes.forEach((turn, index) => {
      const existing = turn.querySelector(':scope > [data-edit-summary]');
      const html = renderTurnEditSummary(turns[index] || [], session, index);
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

  function renderEvent(message, session) {
    message = message || {};
    const kind = eventKind(message);
    const text = eventText(message);
    const messageKey = escapeHTML(message.messageKey || '');
    const anchorAttribute = ` data-message-key="${messageKey}"`;
    if (kind === 'diff') return renderDiff(message);
    if (kind === 'thinking') {
      return `<details class="event thinking-event"${anchorAttribute}><summary><span class="event-icon">◌</span>${escapeHTML(t('thinking'))}</summary><div class="event-body">${renderMarkdown(text)}</div></details>`;
    }
    if (kind === 'tool') {
      const name = cleanTranscriptText(message.toolName || message.name || t('tool'));
      return `<details class="event tool-event"${anchorAttribute}><summary><span class="event-icon">›_</span>${escapeHTML(name)}</summary><div class="event-body">${renderMarkdown(text)}</div></details>`;
    }
    if (kind === 'error') {
      const name = cleanTranscriptText(message.title || message.toolName || t('error'));
      return `<details class="event error-event" open${anchorAttribute}><summary><span class="event-icon">!</span>${escapeHTML(name)}</summary><div class="event-body">${renderMarkdown(text)}</div></details>`;
    }
    if (kind === 'user') {
      return `<div class="turn-prompt"${anchorAttribute}>${longContent(renderMarkdown(text), text)}</div>`;
    }
    const model = cleanTranscriptText(message.model || (session && session.model) || 'Claude');
    const content = renderMarkdown(text);
    return `<div class="assistant-text" data-model="${escapeHTML(model)}"${anchorAttribute}>${content}</div>`;
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
      <div class="waiting-copy"><strong>${escapeHTML(t('waitingTitle'))}</strong><span>${escapeHTML(t('waitingDetail'))}</span></div>
    </div>`;
  }

  function syncClaudeWaiting(root) {
    if (!root) return '';
    root.querySelectorAll('.claude-waiting').forEach(node => node.remove());
    if (!state.waiting) return '';
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
      turns.push(`<section class="turn">${current.prompt}<div class="turn-events">${current.events.join('')}</div>${renderTurnEditSummary(current.messages, session, turns.length)}</section>`);
    };

    messages.forEach(message => {
      if (eventKind(message) === 'user') {
        flush();
        current = {
          prompt: `<header class="turn-header"><span class="turn-label">TURN</span>${renderEvent(message, session)}</header>`,
          events: [],
          messages: []
        };
      } else {
        if (!current) current = { prompt: '<header class="turn-header"><span class="turn-label">TURN</span></header>', events: [], messages: [] };
        current.events.push(renderEvent(message, session));
        current.messages.push(message);
      }
    });
    flush();
    return turns.join('') + (session.awaitingReply ? renderClaudeWaiting() : '');
  }

  function rootElement() {
    return scope && scope.document ? scope.document.getElementById('content') : null;
  }

  function nearBottom() {
    if (!scope || !scope.document) return true;
    return scope.document.body.scrollHeight - scope.scrollY - scope.innerHeight < 120;
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

  async function typeset(targets) {
    if (!scope || !scope.MathJax || typeof scope.MathJax.typesetPromise !== 'function') return;
    try {
      await scope.MathJax.typesetPromise(targets);
    } catch (error) {
      if (scope.console) scope.console.error(error);
    }
  }

  async function setClaudeSession(session) {
    const root = rootElement();
    state.session = Object.assign({}, session, {
      messages: Array.isArray(session && session.messages) ? session.messages.slice() : []
    });
    state.waiting = Boolean(state.session.awaitingReply);
    state.renderedCount = state.session.messages.length;
    if (!root) return renderSession(state.session);
    const shouldFollow = nearBottom();
    root.innerHTML = renderSession(state.session);
    await typeset([root]);
    if (shouldFollow && typeof scope.scrollTo === 'function') {
      scope.scrollTo({ top: scope.document.body.scrollHeight, behavior: 'auto' });
    }
    captureViewportAnchor();
    return root.innerHTML;
  }

  // 原生侧在追加渲染时只发元数据（不含 messages），所以必须先同步确认这边
  // 还持有同一个会话；不匹配就让原生改发完整快照，而不是拿空 messages 去渲染。
  function sessionMatches(session) {
    if (!state.session || !session) return false;
    const mine = state.session.sessionId || '';
    const theirs = session.sessionId || '';
    return mine.length > 0 && mine === theirs;
  }

  async function appendClaudeMessages(session, newMessages) {
    const incoming = Array.isArray(newMessages) ? newMessages : [];
    if (!sessionMatches(session)) {
      // 只有携带 messages 的完整快照才能安全重建；否则交回原生重发。
      if (session && Array.isArray(session.messages)) return setClaudeSession(session);
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
    if (!root || !incoming.length) return renderSession(state.session);

    const shouldFollow = nearBottom();
    root.querySelectorAll('.claude-waiting').forEach(node => node.remove());
    const addedNodes = [];
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

    incoming.forEach(message => {
      if (eventKind(message) === 'user') {
        appendHTML(root,
          `<section class="turn"><header class="turn-header"><span class="turn-label">TURN</span>${renderEvent(message, state.session)}</header><div class="turn-events"></div></section>`);
        return;
      }
      let turn = root.querySelector('section.turn:last-of-type');
      if (!turn) turn = emptyTurn();
      const events = turn.querySelector('.turn-events');
      appendHTML(events, renderEvent(message, state.session));
    });
    refreshTurnEditSummaries(root, state.session);
    syncClaudeWaiting(root);
    await typeset(addedNodes);
    if (shouldFollow && typeof scope.scrollTo === 'function') {
      const reduce = scope.matchMedia && scope.matchMedia('(prefers-reduced-motion: reduce)').matches;
      scope.scrollTo({ top: scope.document.body.scrollHeight, behavior: reduce ? 'auto' : 'smooth' });
    }
    captureViewportAnchor();
    return root.innerHTML;
  }

  installQuoteMenu();
  installGitReviewBridge();
  installStableViewport();

  return {
    cleanTranscriptText,
    inlineMarkup,
    renderMarkdown,
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
    setClaudeSession,
    appendClaudeMessages,
    sessionMatches
  };
});
