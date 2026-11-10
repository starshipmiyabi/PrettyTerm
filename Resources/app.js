(function (scope, factory) {
  const api = factory(scope);
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (scope) {
    scope.PrettyTermRenderer = api;
    scope.setClaudeSession = api.setClaudeSession;
    scope.appendClaudeMessages = api.appendClaudeMessages;
    scope.updateClaudeMessages = api.updateClaudeMessages;
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
  const virtualCandidates = new Set();
  const pinnedVirtualBodies = new Set();
  const messageByKey = new Map();
  let virtualObserver = null;
  let liveRendering = false;
  let nextBodyID = 0;
  let virtualUpdateTimer = null;

  function renderLive(render) {
    liveRendering = true;
    try { return render(); }
    finally { liveRendering = false; }
  }

  function virtualBlock(className, render, height, attributes = '', extra = {}) {
    const id = String(++nextBodyID);
    virtualBodies.set(id, Object.assign({ id, render, mounted: false, height, node: null,
      visible: false, ui: null }, extra));
    return `<div class="${className}"${attributes} data-virtual-body="${id}" style="min-height:${height}px;display:flow-root;box-sizing:border-box"></div>`;
  }

  function contentBody(className, text, render, attributes = '') {
    if (!liveRendering) return `<div class="${className}"${attributes}>${render()}</div>`;
    const columns = Math.max(1, Math.floor(((scope.innerWidth || 720) - 100) / 8));
    const lines = String(text).split('\n').reduce((total, line) => total + Math.max(1, Math.ceil(line.length / columns)), 0);
    return virtualBlock(className, render, Math.max(24, lines * 24), attributes);
  }

  function ownedElements(node, selector) {
    return Array.from(node.querySelectorAll(selector)).filter(item => item.closest('[data-virtual-body]') === node);
  }

  function virtualChildren(node) {
    return Array.from(node.querySelectorAll('[data-virtual-body]')).filter(child =>
      child.parentElement.closest('[data-virtual-body]') === node);
  }

  function rememberVirtualChildren(node) {
    return virtualChildren(node).map(child => {
      const record = virtualBodies.get(child.dataset.virtualBody);
      return { ui: record.mounted ? captureVirtualUI(child) : record.ui,
        height: record.mounted ? child.getBoundingClientRect().height : record.height,
        children: record.mounted ? rememberVirtualChildren(child) : record.children };
    });
  }

  function restoreVirtualChildren(node, children) {
    if (!children) return;
    virtualChildren(node).forEach((child, index) => {
      const saved = children[index];
      if (!saved) return;
      const record = virtualBodies.get(child.dataset.virtualBody);
      record.ui = saved.ui;
      record.children = saved.children;
      if (saved.height > 0) { record.height = saved.height; child.style.minHeight = `${saved.height}px`; }
    });
  }

  // Save interaction state as values, without retaining detached DOM trees.
  function captureVirtualUI(node) {
    return {
      details: ownedElements(node, 'details').map(item => item.open),
      images: ownedElements(node, '.message-image').map(item => item.getAttribute('aria-expanded')),
      diagrams: ownedElements(node, '.diagram-block').map(item => ({
        source: item.querySelector('pre code').textContent.trim(),
        state: item.dataset.state,
        view: item.dataset.view,
        error: item.querySelector('.diagram-error').textContent,
        zoom: Number(item.dataset.zoom) || 1,
        scrollLeft: (diagramScrollPositions.get(item) || {}).left ?? item.querySelector('.diagram-canvas').scrollLeft,
        scrollTop: (diagramScrollPositions.get(item) || {}).top ?? item.querySelector('.diagram-canvas').scrollTop
      })),
      inputs: ownedElements(node, 'input, textarea').map(item => ({ value: item.value, checked: item.checked })),
      options: ownedElements(node, '.question-option').map(item => item.classList.contains('selected')),
      submitted: ownedElements(node, '.question-card').map(item => item.classList.contains('submitted'))
    };
  }

  function restoreVirtualUI(node, ui) {
    if (!ui) return;
    ownedElements(node, 'details').forEach((item, index) => { if (index < ui.details.length) item.open = ui.details[index]; });
    ownedElements(node, '.message-image').forEach((item, index) => { if (index < ui.images.length) item.setAttribute('aria-expanded', ui.images[index]); });
    ownedElements(node, '.diagram-block').forEach((item, index) => {
      const saved = (ui.diagrams || [])[index];
      if (!saved || item.querySelector('pre code').textContent.trim() !== saved.source) return;
      item.dataset.zoom = saved.zoom || 1;
      diagramScrollPositions.set(item, { left: saved.scrollLeft || 0, top: saved.scrollTop || 0 });
      if (saved.view === 'source') item.dataset.view = 'source';
      if (saved.state === 'ready' || saved.state === 'rendering') {
        // Retain the user's render request even when its cached SVG was evicted.
        item.dataset.state = 'rendering';
      } else if (saved.state === 'error') {
        item.dataset.state = 'error';
        item.querySelector('.diagram-error').textContent = saved.error;
      }
    });
    ownedElements(node, 'input, textarea').forEach((item, index) => {
      if (index < ui.inputs.length) { item.value = ui.inputs[index].value; item.checked = ui.inputs[index].checked; }
    });
    ownedElements(node, '.question-option').forEach((item, index) => {
      if (index < ui.options.length) { item.classList.toggle('selected', ui.options[index]); item.setAttribute('aria-pressed', String(ui.options[index])); }
    });
    ownedElements(node, '.question-card').forEach((item, index) => {
      if (!ui.submitted[index] || item.classList.contains('answered')) return;
      item.classList.add('submitted');
      const button = item.querySelector('.question-submit');
      if (button) { button.disabled = true; button.textContent = t('askUserSent'); }
    });
  }

  function releaseVirtualContent(node, mathJax, includeRoot = false) {
    if (mathJax && mathJax.typesetClear) mathJax.typesetClear([node]);
    const nodes = Array.from(node.querySelectorAll('[data-virtual-body]'));
    if (includeRoot && node.dataset && node.dataset.virtualBody) nodes.push(node);
    nodes.forEach(child => {
      const record = virtualBodies.get(child.dataset.virtualBody);
      if (!record) return;
      if (virtualObserver) virtualObserver.unobserve(child);
      virtualCandidates.delete(record);
      pinnedVirtualBodies.delete(record);
      virtualBodies.delete(record.id);
    });
  }

  function resetVirtualContent(root, mathJax) {
    if (root) releaseVirtualContent(root, mathJax);
    if (virtualObserver) virtualObserver.disconnect();
    virtualBodies.clear();
    virtualCandidates.clear();
    pinnedVirtualBodies.clear();
  }

  function registerVirtualContent(root) {
    if (!root) return;
    const nodes = Array.from(root.querySelectorAll('[data-virtual-body]'));
    if (root.dataset && root.dataset.virtualBody) nodes.unshift(root);
    for (const node of nodes) {
      const record = virtualBodies.get(node.dataset.virtualBody);
      if (!record || record.node === node) continue;
      record.node = node;
      virtualCandidates.add(record);
      if (virtualObserver) virtualObserver.observe(node);
    }
  }

  function updateVirtualBodies(mathJax) {
    const added = [];
    const selection = scope.getSelection();
    // Newly inserted shells are measured once. Subsequent scroll work is driven
    // by intersection changes, rather than scanning the entire transcript.
    while (virtualCandidates.size) {
      const candidates = Array.from(virtualCandidates);
      virtualCandidates.clear();
      const changes = candidates.filter(record => record.node && record.node.isConnected).map(record => {
        const node = record.node;
        const rect = node.getBoundingClientRect();
        const closed = Boolean(node.closest('details:not([open])'));
        const selected = record.mounted && selection && !selection.isCollapsed && selection.containsNode(node, true);
        const focused = record.mounted && node.contains(scope.document.activeElement);
        const visible = !closed && rect.bottom >= -scope.innerHeight && rect.top <= scope.innerHeight * 2;
        record.visible = visible;
        return { record, rect, wanted: selected || focused || visible, pinned: selected || focused };
      });
      for (const { record, rect, wanted, pinned } of changes) {
        const node = record.node;
        if (!node.isConnected || !virtualBodies.has(record.id)) continue;
        if (pinned) pinnedVirtualBodies.add(record); else pinnedVirtualBodies.delete(record);
        if (wanted === record.mounted) continue;
        if (wanted) {
          node.style.minHeight = '';
          node.innerHTML = record.render(record);
          record.mounted = true;
          restoreVirtualUI(node, record.ui);
          restoreVirtualChildren(node, record.children);
          registerVirtualContent(node);
          added.push(node);
        } else {
          record.ui = captureVirtualUI(node);
          record.children = rememberVirtualChildren(node);
          if (rect.height) record.height = rect.height;
          releaseVirtualContent(node, mathJax);
          node.replaceChildren();
          node.style.minHeight = `${record.height}px`;
          record.mounted = false;
        }
      }
    }
    return added;
  }

  function scheduleVirtualContent() {
    if (virtualUpdateTimer !== null) return;
    virtualUpdateTimer = scope.requestAnimationFrame(() => {
      virtualUpdateTimer = null;
      if (virtualCandidates.size) typeset([]);
    });
  }

  function installVirtualContent() {
    if (!scope || !scope.document || !scope.addEventListener) return;
    const observe = () => {
      if (virtualObserver) virtualObserver.disconnect();
      virtualObserver = new scope.IntersectionObserver(entries => {
        for (const entry of entries) {
          const record = virtualBodies.get(entry.target.dataset.virtualBody);
          if (record) virtualCandidates.add(record);
        }
        scheduleVirtualContent();
      }, { rootMargin: `${scope.innerHeight}px 0px` });
      for (const record of virtualBodies.values()) {
        if (record.node && record.node.isConnected) {
          virtualObserver.observe(record.node);
          virtualCandidates.add(record);
        }
      }
    };
    observe();
    scope.addEventListener('resize', () => { observe(); scheduleVirtualContent(); });
    scope.document.addEventListener('toggle', event => {
      registerVirtualContent(event.target);
      event.target.querySelectorAll('[data-virtual-body]').forEach(node => {
        const record = virtualBodies.get(node.dataset.virtualBody);
        if (record) virtualCandidates.add(record);
      });
      scheduleVirtualContent();
    }, true);
    const releasePinned = () => {
      for (const record of pinnedVirtualBodies) virtualCandidates.add(record);
      scheduleVirtualContent();
    };
    scope.document.addEventListener('selectionchange', releasePinned);
    scope.document.addEventListener('focusout', releasePinned);
  }

  const strings = {
    'zh-Hans': {
      quote: '引用选中内容', expandInput: '展开输入', lines: '行', codeChange: '代码改动',
      copyOutput: '复制', copyCode: '复制代码', copied: '已复制', code: '代码',
      diagramShowSource: '源码', diagramShowDiagram: '图表', diagramError: '图表无法渲染，已显示源码：',
      diagramRender: '渲染', diagramRendering: '渲染中…',
      diagramZoom: '图表缩放', diagramZoomIn: '放大', diagramZoomOut: '缩小', diagramZoomReset: '重置缩放',
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
      copyOutput: 'Copy', copyCode: 'Copy code', copied: 'Copied', code: 'Code',
      diagramShowSource: 'Source', diagramShowDiagram: 'Diagram', diagramError: 'Diagram could not be rendered; showing source: ',
      diagramRender: 'Render', diagramRendering: 'Rendering…',
      diagramZoom: 'Diagram zoom', diagramZoomIn: 'Zoom in', diagramZoomOut: 'Zoom out', diagramZoomReset: 'Reset zoom',
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

  const wordSet = value => new Set(value.split(' '));
  const CODE_LANGUAGE_NAMES = {
    bash: 'Bash', sh: 'Shell', shell: 'Shell', zsh: 'Zsh', console: 'Console',
    python: 'Python', py: 'Python', javascript: 'JavaScript', js: 'JavaScript', jsx: 'JSX',
    typescript: 'TypeScript', ts: 'TypeScript', tsx: 'TSX', json: 'JSON',
    objc: 'Objective-C', 'objective-c': 'Objective-C', objectivec: 'Objective-C',
    c: 'C', cpp: 'C++', 'c++': 'C++', swift: 'Swift', go: 'Go', rust: 'Rust', rs: 'Rust',
    java: 'Java', kotlin: 'Kotlin', html: 'HTML', css: 'CSS', yaml: 'YAML', yml: 'YAML', mermaid: 'Mermaid',
    sql: 'SQL', latex: 'LaTeX', tex: 'LaTeX', markdown: 'Markdown', md: 'Markdown', diff: 'Diff',
    patch: 'Diff', toml: 'TOML', ini: 'INI', env: '.env', dockerfile: 'Dockerfile',
    makefile: 'Makefile', fish: 'Fish', ruby: 'Ruby', rb: 'Ruby', r: 'R', julia: 'Julia',
    jl: 'Julia', lua: 'Lua', php: 'PHP', scala: 'Scala', dart: 'Dart', cs: 'C#', csharp: 'C#',
    cu: 'CUDA', cuda: 'CUDA', xml: 'XML', vue: 'Vue', svelte: 'Svelte', scss: 'SCSS',
    less: 'Less', perl: 'Perl', pl: 'Perl', kt: 'Kotlin', jsonl: 'JSON Lines'
  };
  const CODE_FAMILIES = {};
  [
    ['shell', 'bash sh shell zsh console terminal fish ksh dockerfile docker makefile make mk'],
    ['python', 'python py python3 pyw pyi ipython'],
    ['json', 'json jsonl ndjson geojson webmanifest'],
    ['clike', 'javascript js jsx mjs cjs typescript ts tsx mts cts objc objective-c objectivec m mm c h cpp c++ cc cxx hpp hh hxx cu cuh cuda swift go golang rust rs java kotlin kt kts scala sc dart cs csharp php groovy gradle zig proto glsl hlsl metal jsonc json5'],
    ['yaml', 'yaml yml'],
    ['ini', 'toml ini cfg conf config env dotenv properties editorconfig gitconfig'],
    ['markup', 'html htm xhtml xml svg vue svelte plist xaml xsl'],
    ['css', 'css scss sass less'],
    ['sql', 'sql psql mysql sqlite pgsql'],
    ['latex', 'tex latex sty cls bib'],
    ['lua', 'lua'],
    ['hash', 'ruby rb rake gemspec r julia jl perl pl pm elixir ex exs nim'],
    ['diff', 'diff patch']
  ].forEach(([family, names]) => names.split(' ').forEach(name => { CODE_FAMILIES[name] = family; }));
  const CODE_KEYWORDS = {
    shell: wordSet('if then else elif fi for while until do done case esac in function select return exit export local readonly declare unset source alias sudo time exec nohup end set begin switch FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL MAINTAINER'),
    python: wordSet('and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case'),
    clike: wordSet('abstract as async await break case catch class const continue default defer delete do else enum export extends extern final finally fn for func function go guard if impl implements import in instanceof interface let loop match mod module mut new package private protected protocol pub public return static struct super switch throw throws try type typedef typeof union unsafe use var void volatile where while yield extension init deinit lazy weak override include define ifdef ifndef endif pragma property nonatomic strong readonly implementation end namespace using template typename operator virtual friend inline constexpr noexcept auto sizeof goto signed unsigned long short int float double char bool fun val trait sealed internal companion chan range fallthrough __global__ __device__ __host__ __shared__ __constant__'),
    lua: wordSet('and break do else elseif end for function goto if in local not or repeat return then until while'),
    hash: wordSet('if else elsif elseif unless while until for foreach in do end def class module return yield begin rescue ensure raise then case when break next redo retry function repeat library require require_relative include import using export struct mutable let local global const my our sub use package defmodule defp fn quote macro abstract type and or not alias')
  };
  const CODE_LITERALS = wordSet('true false null undefined nil NULL None True False TRUE FALSE YES NO NA Inf NaN nothing this self');
  const CONFIG_LITERALS = wordSet('true false null yes no on off True False Null Yes No On Off TRUE FALSE NULL YES NO ON OFF ~');
  const SQL_KEYWORDS = wordSet('SELECT FROM WHERE AND OR NOT INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP ALTER ADD INDEX VIEW PRIMARY KEY FOREIGN REFERENCES JOIN INNER LEFT RIGHT FULL OUTER CROSS ON AS GROUP BY ORDER HAVING LIMIT OFFSET UNION ALL DISTINCT CASE WHEN THEN ELSE END IS IN LIKE BETWEEN EXISTS WITH RETURNING DEFAULT CONSTRAINT UNIQUE CHECK ASC DESC BEGIN COMMIT ROLLBACK TRANSACTION IF REPLACE DATABASE SCHEMA GRANT REVOKE TRIGGER PROCEDURE FUNCTION RETURNS DECLARE INTEGER INT BIGINT SMALLINT TEXT VARCHAR CHAR BOOLEAN REAL FLOAT DOUBLE DECIMAL NUMERIC DATE TIMESTAMP SERIAL AUTOINCREMENT');
  const SQL_LITERALS = wordSet('NULL TRUE FALSE');
  const SHELL_COMMAND_PREFIXES = wordSet('if then else elif do while until sudo time exec nohup RUN CMD ENTRYPOINT');
  const LINE_ANCHORED_FAMILIES = wordSet('yaml ini diff');
  const NUMBER_RULE = /\b(?:0[xX][\da-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/;
  const CODE_RULES = {
    shell: [
      ['comment', /#.*/],
      ['string', /'[^']*'|"(?:\\[\s\S]|[^"\\])*"/],
      ['variable', /\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?*$!]/],
      ['flag', /--?[A-Za-z][\w-]*/],
      ['word', /[\w./~:@%+,=-]+/]
    ],
    python: [
      ['comment', /#.*/],
      ['string', /[rRbBuUfF]{0,2}(?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')/],
      ['number', NUMBER_RULE],
      ['decorator', /@[A-Za-z_][\w.]*/],
      ['word', /[A-Za-z_]\w*/]
    ],
    clike: [
      ['comment', /\/\/.*|\/\*[\s\S]*?(?:\*\/|$)/],
      ['string', /@?"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\[\s\S]|[^`\\])*`/],
      ['number', NUMBER_RULE],
      ['word', /[A-Za-z_$][\w$]*/]
    ],
    json: [
      ['string', /"(?:\\.|[^"\\\n])*"/],
      ['number', /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/],
      ['word', /[A-Za-z_]\w*/]
    ],
    yaml: [
      ['comment', /#.*/],
      ['property', /[A-Za-z_][\w.-]*(?=[ \t]*:(?:[ \t]|$))/],
      ['string', /"(?:\\.|[^"\\\n])*"|'(?:''|[^'\n])*'/],
      ['variable', /[&*][A-Za-z_][\w-]*/],
      ['number', NUMBER_RULE],
      ['word', /[A-Za-z_~][\w-]*/]
    ],
    ini: [
      ['comment', /^[ \t]*[#;].*|[ \t]#.*/],
      ['keyword', /^[ \t]*\[\[?[^\]\n]*\]\]?/],
      ['property', /^[ \t]*(?:export[ \t]+)?[A-Za-z_][\w.-]*(?=[ \t]*[=:])/],
      ['string', /"(?:\\.|[^"\\\n])*"|'[^'\n]*'/],
      ['variable', /\$\{[^}\n]*\}|\$[A-Za-z_]\w*/],
      ['number', NUMBER_RULE],
      ['word', /[A-Za-z_][\w-]*/]
    ],
    markup: [
      ['comment', /<!--[\s\S]*?(?:-->|$)/],
      ['keyword', /<![A-Za-z][^>]*>|<\?[\s\S]*?\?>/],
      ['tag', /<\/?[A-Za-z][\w:.-]*/],
      ['tagEnd', /\/?>/],
      ['string', /"[^"]*"|'[^']*'/],
      ['entity', /&#?\w+;/],
      ['word', /[A-Za-z_:@#][\w:.-]*/]
    ],
    css: [
      ['comment', /\/\*[\s\S]*?(?:\*\/|$)|\/\/.*/],
      ['string', /"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'/],
      ['keyword', /@[\w-]+/],
      ['variable', /\$[\w-]+|--[\w-]+/],
      ['color', /#[\da-fA-F]{3,8}\b/],
      ['number', /-?(?:\d+\.?\d*|\.\d+)(?:%|[A-Za-z]+)?/],
      ['word', /[A-Za-z_-][\w-]*/]
    ],
    sql: [
      ['comment', /--.*|\/\*[\s\S]*?(?:\*\/|$)/],
      ['string', /'(?:''|[^'])*'/],
      ['property', /"[^"\n]*"|`[^`\n]*`/],
      ['number', NUMBER_RULE],
      ['word', /[A-Za-z_][\w$]*/]
    ],
    latex: [
      ['string', /\$\$[\s\S]*?\$\$|\$(?:\\.|[^$\\\n])+\$|\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\]/],
      ['keyword', /\\(?:[A-Za-z@]+\*?|[^A-Za-z@\n])/],
      ['comment', /%.*/]
    ],
    lua: [
      ['comment', /--\[\[[\s\S]*?(?:\]\]|$)|--.*/],
      ['string', /"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\[\[[\s\S]*?\]\]/],
      ['number', NUMBER_RULE],
      ['word', /[A-Za-z_]\w*/]
    ],
    hash: [
      ['comment', /#.*/],
      ['string', /"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'/],
      ['number', NUMBER_RULE],
      ['variable', /[@$][A-Za-z_]\w*|:[A-Za-z_]\w*/],
      ['word', /[A-Za-z_]\w*[?!]?/]
    ],
    diff: [
      ['keyword', /^(?:diff |index |--- |\+\+\+ ).*/],
      ['property', /^@@.*/],
      ['string', /^\+.*/],
      ['variable', /^-.*/]
    ]
  };
  const CODE_PATTERNS = new Map();
  const CODE_HIGHLIGHT_LIMIT = 300000;

  function codePattern(family) {
    if (!CODE_PATTERNS.has(family)) {
      const source = CODE_RULES[family].map(([, rule]) => `(${rule.source})`).join('|');
      CODE_PATTERNS.set(family, new RegExp(source, LINE_ANCHORED_FAMILIES.has(family) ? 'gm' : 'g'));
    }
    return CODE_PATTERNS.get(family);
  }

  // Returns [className, text] pairs; className '' means unstyled text.
  function codeTokens(language, source) {
    const text = String(source == null ? '' : source);
    const family = CODE_FAMILIES[String(language || '').toLowerCase()];
    if (!family || text.length > CODE_HIGHLIGHT_LIMIT) return [['', text]];
    const rules = CODE_RULES[family];
    const keywords = CODE_KEYWORDS[family] || new Set();
    const pattern = codePattern(family);
    pattern.lastIndex = 0;
    const tokens = [];
    let cursor = 0;
    let commandPosition = true;
    let inTag = false;
    let depth = 0;
    const plain = value => {
      if (!value) return;
      // A trailing backslash continues the same shell command on the next line.
      if (family === 'shell' && /\n|\|\|?|&&|;|\(|`/.test(value.replace(/\\\n/g, ''))) commandPosition = true;
      if (family === 'css') {
        for (const character of value) {
          if (character === '{') depth++;
          else if (character === '}') depth = Math.max(0, depth - 1);
        }
      }
      tokens.push(['', value]);
    };
    let match;
    while ((match = pattern.exec(text))) {
      const value = match[0];
      if (!value) {
        pattern.lastIndex++;
        continue;
      }
      plain(text.slice(cursor, match.index));
      cursor = match.index;
      const kind = rules[match.slice(1).findIndex(group => group !== undefined)][0];
      const previous = match.index > 0 ? text[match.index - 1] : '\n';
      const following = text.slice(pattern.lastIndex, pattern.lastIndex + 40);
      let className = kind;
      if (family === 'shell') {
        if ((kind === 'comment' || kind === 'flag') && !/\s/.test(previous)) className = null;
        else if (kind === 'word') {
          if (!commandPosition) className = '';
          else if (/^[A-Za-z_]\w*=/.test(value)) className = 'variable';
          else className = keywords.has(value) ? 'keyword' : 'command';
        }
      } else if (family === 'markup') {
        if (kind === 'tag') {
          className = 'keyword';
          inTag = true;
        } else if (kind === 'tagEnd') {
          className = inTag ? 'keyword' : '';
          inTag = false;
        } else if (kind === 'string') className = inTag ? 'string' : null;
        else if (kind === 'entity') className = 'literal';
        else if (kind === 'word') className = inTag ? 'property' : '';
      } else if (family === 'css') {
        if (kind === 'comment' && value.startsWith('//') && !/\s/.test(previous)) className = null;
        else if (kind === 'color') className = depth > 0 ? 'number' : 'function';
        else if (kind === 'word') {
          if (/^\(/.test(following)) className = 'function';
          else if (depth > 0) className = /^[ \t]*:(?!:)/.test(following) ? 'property' : '';
          else className = 'function';
        }
      } else if (family === 'sql') {
        if (kind === 'word') {
          const upper = value.toUpperCase();
          if (SQL_LITERALS.has(upper)) className = 'literal';
          else if (SQL_KEYWORDS.has(upper)) className = 'keyword';
          else className = /^[ \t]*\(/.test(following) ? 'function' : '';
        }
      } else if (family === 'yaml' || family === 'ini') {
        if (kind === 'comment' && family === 'yaml' && !/\s/.test(previous)) className = null;
        else if (kind === 'word') className = CONFIG_LITERALS.has(value) ? 'literal' : '';
      } else if (kind === 'word') {
        if (CODE_LITERALS.has(value)) className = 'literal';
        else if (keywords.has(value)) className = 'keyword';
        else className = /^[ \t]*\(/.test(following) ? 'function' : '';
      } else if (kind === 'string' && family === 'json') {
        className = /^\s*:/.test(following) ? 'property' : 'string';
      }
      if (className === null) {
        plain(value[0]);
        cursor = match.index + 1;
        pattern.lastIndex = cursor;
        continue;
      }
      if (family === 'shell' && kind !== 'comment') {
        if (className === 'keyword') commandPosition = SHELL_COMMAND_PREFIXES.has(value);
        else if (!(kind === 'word' && className === 'variable')) commandPosition = false;
      }
      tokens.push([className, value]);
      cursor = pattern.lastIndex;
    }
    plain(text.slice(cursor));
    return tokens;
  }

  function tokenHTML(className, value) {
    return className ? `<span class="tok-${className}">${escapeHTML(value)}</span>` : escapeHTML(value);
  }

  function highlightCode(language, source) {
    return codeTokens(language, source).map(([className, value]) => tokenHTML(className, value)).join('');
  }

  // Splits multi-line tokens so each source line stays independently well-formed.
  function highlightCodeLines(language, source) {
    const lines = [''];
    codeTokens(language, source).forEach(([className, value]) => {
      value.split('\n').forEach((part, index) => {
        if (index > 0) lines.push('');
        if (part) lines[lines.length - 1] += tokenHTML(className, part);
      });
    });
    return lines;
  }

  function fileLanguage(title) {
    const name = String(title || '').toLowerCase();
    const special = {
      dockerfile: 'dockerfile', containerfile: 'dockerfile', makefile: 'makefile',
      gnumakefile: 'makefile', '.bashrc': 'bash', '.bash_profile': 'bash', '.profile': 'sh',
      '.zshrc': 'zsh', '.zprofile': 'zsh', '.zshenv': 'zsh', '.env': 'env',
      '.gitconfig': 'ini', '.editorconfig': 'ini'
    };
    if (Object.prototype.hasOwnProperty.call(special, name)) return special[name];
    if (name.startsWith('dockerfile.') || name.endsWith('.dockerfile')) return 'dockerfile';
    if (name.startsWith('.env.')) return 'env';
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.slice(dot + 1) : '';
  }

  // `closed` is false for a fence that never saw its closing line, i.e. text
  // still being streamed. Those stay plain code so half-written diagrams are
  // never handed to the Mermaid parser.
  function renderCodeBlock(language, lines, closed = true) {
    const name = String(language || '').trim().split(/\s+/)[0];
    const label = CODE_LANGUAGE_NAMES[name.toLowerCase()] || name || t('code');
    const languageClass = name ? ` class="language-${escapeHTML(name)}"` : '';
    const diagram = closed && name.toLowerCase() === 'mermaid';
    // Diagrams are compiled by hand: a block starts "idle" showing its source,
    // the Render button moves it to "rendering", then "ready" or "error". The
    // source <pre> stays in the DOM (copy reads it, and it is the fallback
    // view); CSS swaps it for the rendered canvas once data-state is "ready".
    const toggle = diagram
      ? `<button type="button" class="diagram-render"><span class="diagram-render-idle">${escapeHTML(t('diagramRender'))}</span><span class="diagram-render-busy">${escapeHTML(t('diagramRendering'))}</span></button>` +
        `<button type="button" class="diagram-toggle"><span class="diagram-toggle-source">${escapeHTML(t('diagramShowSource'))}</span><span class="diagram-toggle-diagram">${escapeHTML(t('diagramShowDiagram'))}</span></button>`
      : '';
    const canvas = diagram
      ? '<div class="diagram-canvas" role="img" aria-label="Mermaid"></div><div class="diagram-error" role="status"></div>'
      : '';
    const zoom = diagram
      ? `<span class="diagram-zoom-controls" role="group" aria-label="${escapeHTML(t('diagramZoom'))}">` +
        `<button type="button" class="diagram-zoom-button" data-diagram-zoom="out" title="${escapeHTML(t('diagramZoomOut'))}" aria-label="${escapeHTML(t('diagramZoomOut'))}">−</button>` +
        `<button type="button" class="diagram-zoom-button diagram-zoom-reset" data-diagram-zoom="reset" title="${escapeHTML(t('diagramZoomReset'))}" aria-label="${escapeHTML(t('diagramZoomReset'))}">100%</button>` +
        `<button type="button" class="diagram-zoom-button" data-diagram-zoom="in" title="${escapeHTML(t('diagramZoomIn'))}" aria-label="${escapeHTML(t('diagramZoomIn'))}">+</button></span>`
      : '';
    return `<div class="code-block${diagram ? ' diagram-block' : ''}"${diagram ? ' data-state="idle"' : ''}><div class="code-block-header"><span class="code-block-language"><span class="code-block-icon" aria-hidden="true">&lt;/&gt;</span>${escapeHTML(label)}</span>${toggle}${zoom}<button type="button" class="code-copy-button" title="${escapeHTML(t('copyCode'))}" aria-label="${escapeHTML(t('copyCode'))}"><span class="code-copy-icon" aria-hidden="true">⧉</span><span class="code-copy-done">✓ ${escapeHTML(t('copied'))}</span></button></div>${canvas}<pre><code${languageClass}>${highlightCode(name, lines.join('\n'))}</code></pre></div>`;
  }

  // Mermaid diagrams are compiled only when the user presses Render, so the
  // library (~5 MB) and the SVGs cost nothing until asked for. Virtual
  // scrolling discards off-screen DOM, so finished SVG strings are cached under
  // a size budget; a remounted block whose source is cached comes back as a
  // chart without another click (and without loading the library again). The
  // saved interaction state retains the render request if the cache was evicted.
  const DIAGRAM_CACHE_MAX_ENTRIES = 50;
  const DIAGRAM_CACHE_MAX_CHARS = 8 * 1024 * 1024;

  function createDiagramCache(maxEntries = DIAGRAM_CACHE_MAX_ENTRIES, maxChars = DIAGRAM_CACHE_MAX_CHARS) {
    const entries = new Map();
    let chars = 0;
    return {
      get(key) {
        if (!entries.has(key)) return undefined;
        const value = entries.get(key);
        entries.delete(key);
        entries.set(key, value);
        return value;
      },
      set(key, value) {
        if (value.length > maxChars) return;
        if (entries.has(key)) { chars -= entries.get(key).length; entries.delete(key); }
        entries.set(key, value);
        chars += value.length;
        for (const [oldest, text] of entries) {
          if (entries.size <= maxEntries && chars <= maxChars) break;
          entries.delete(oldest);
          chars -= text.length;
        }
      },
      get size() { return entries.size; },
      get chars() { return chars; }
    };
  }

  const diagramCache = createDiagramCache();
  let diagramQueue = Promise.resolve();
  let mermaidLoad = null;
  let mermaidThemeSignature = '';
  let nextDiagramID = 0;
  const diagramTasks = new WeakMap();
  const diagramScrollPositions = new WeakMap();

  function refreshDiagramViewport(block) {
    const canvas = block.querySelector('.diagram-canvas');
    const svg = canvas && canvas.querySelector && canvas.querySelector('svg');
    if (!svg || !svg.viewBox || !canvas.clientWidth) return;
    const box = svg.viewBox.baseVal;
    if (!(box.width > 0 && box.height > 0)) return;
    const style = scope.getComputedStyle(canvas);
    const horizontalPadding = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
    const verticalPadding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
    const width = Math.min(box.width, canvas.clientWidth - horizontalPadding);
    const height = width * box.height / box.width;
    const zoom = Number(block.dataset.zoom) || 1;
    // Keep the fitted viewport's height while the SVG grows inside it.
    canvas.style.height = `${height + verticalPadding}px`;
    svg.style.maxWidth = 'none';
    svg.style.width = `${width * zoom}px`;
    svg.style.height = `${height * zoom}px`;
    block.querySelector('.diagram-zoom-reset').textContent = `${Math.round(zoom * 100)}%`;
    const saved = diagramScrollPositions.get(block);
    if (saved) {
      canvas.scrollLeft = saved.left;
      canvas.scrollTop = saved.top;
      diagramScrollPositions.delete(block);
    }
  }

  function zoomDiagram(block, zoom, point) {
    if (!Number.isFinite(zoom) || zoom <= 0) return;
    const canvas = block.querySelector('.diagram-canvas');
    const svg = canvas.querySelector('svg');
    if (!svg) return;
    const viewport = canvas.getBoundingClientRect();
    const previous = svg.getBoundingClientRect();
    const x = point ? point.clientX : viewport.left + canvas.clientWidth / 2;
    const y = point ? point.clientY : viewport.top + canvas.clientHeight / 2;
    const oldZoom = Number(block.dataset.zoom) || 1;
    const diagramX = (x - previous.left) / oldZoom;
    const diagramY = (y - previous.top) / oldZoom;
    block.dataset.zoom = zoom;
    refreshDiagramViewport(block);
    const next = svg.getBoundingClientRect();
    canvas.scrollLeft += next.left + diagramX * zoom - x;
    canvas.scrollTop += next.top + diagramY * zoom - y;
  }

  function loadMermaid() {
    if (scope.mermaid) return Promise.resolve(scope.mermaid);
    if (mermaidLoad) return mermaidLoad;
    mermaidLoad = new Promise((resolve, reject) => {
      const script = scope.document.createElement('script');
      script.src = 'mermaid.min.js';
      script.onload = () => scope.mermaid ? resolve(scope.mermaid) : reject(new Error('Mermaid did not initialise'));
      script.onerror = () => { script.remove(); reject(new Error('Mermaid failed to load')); };
      scope.document.head.appendChild(script);
    });
    // A failed load is retried by the next diagram instead of sticking forever.
    mermaidLoad.catch(() => { mermaidLoad = null; });
    return mermaidLoad;
  }

  // Colours come from the page's CSS variables so diagrams follow the warm
  // palette and its dark variant, and a system appearance change is picked up
  // by the next render.
  function diagramConfig() {
    const root = scope.document.documentElement;
    const style = typeof scope.getComputedStyle === 'function' ? scope.getComputedStyle(root) : null;
    const read = (name, fallback) => (style && style.getPropertyValue(name).trim()) || fallback;
    const body = scope.document.body;
    const fontFamily = (style && body && scope.getComputedStyle(body).fontFamily) ||
      '-apple-system, "PingFang SC", sans-serif';
    const dark = Boolean(scope.matchMedia && scope.matchMedia('(prefers-color-scheme: dark)').matches);
    return {
      startOnLoad: false,
      securityLevel: 'strict',
      suppressErrorRendering: true,
      theme: 'base',
      fontFamily,
      themeVariables: {
        darkMode: dark,
        background: read('--paper', '#fffaf1'),
        primaryColor: read('--blue-soft', '#f4dfc5'),
        primaryTextColor: read('--ink', '#30271f'),
        primaryBorderColor: read('--blue', '#a34717'),
        lineColor: read('--muted', '#7f6e5e'),
        secondaryColor: read('--soft', '#efe2cf'),
        tertiaryColor: read('--paper', '#fffaf1'),
        noteBkgColor: read('--amber-soft', '#f7e3c8'),
        noteTextColor: read('--ink', '#30271f'),
        noteBorderColor: read('--amber', '#9f4c18')
      }
    };
  }

  function diagramKey(config, source) {
    return `${JSON.stringify(config.themeVariables)}${config.fontFamily}\n${source}`;
  }

  // Renders are serialised: Mermaid keeps global state while it measures text.
  function renderDiagramSVG(source) {
    const task = diagramQueue.then(async () => {
      const config = diagramConfig();
      const key = diagramKey(config, source);
      const cached = diagramCache.get(key);
      if (cached !== undefined) return cached;
      const mermaid = await loadMermaid();
      const signature = JSON.stringify(config.themeVariables) + config.fontFamily;
      if (signature !== mermaidThemeSignature) {
        mermaid.initialize(config);
        mermaidThemeSignature = signature;
      }
      const id = `pt-diagram-${++nextDiagramID}`;
      try {
        const { svg } = await mermaid.render(id, source);
        diagramCache.set(key, svg);
        return svg;
      } finally {
        // Mermaid parks scratch elements in <body> while measuring; a failed
        // parse can leave them behind.
        for (const prefix of ['d', 'i']) {
          const scratch = scope.document.getElementById(prefix + id);
          if (scratch) scratch.remove();
        }
      }
    });
    diagramQueue = task.catch(() => {});
    return task;
  }

  // Apply a completed diagram against the current viewport, rather than the
  // viewport from when compilation started. Compilation does not own the
  // transcript update queue or delay virtual content being released.
  function applyDiagramUpdate(block, update) {
    if (!block.isConnected) return false;
    const anchor = rootElement() && (captureViewportAnchor() || state.viewportAnchor);
    update();
    if (block.dataset.state === 'ready') refreshDiagramViewport(block);
    if (anchor) restoreViewportAnchor();
    return true;
  }

  // Handles the diagram blocks inside `targets` on their own compilation queue.
  //  - "rendering" blocks (Render was pressed) are compiled;
  //  - "idle" blocks are only restored, and only if their SVG is still cached;
  //  - blocks inside a streaming message are skipped (the message is rebuilt on
  //    every update) and picked up once it settles.
  async function renderDiagrams(targets) {
    if (!scope.document || !scope.document.documentElement) return false;
    const actionable = '.diagram-block[data-state="idle"], .diagram-block[data-state="rendering"]';
    const blocks = new Set();
    for (const target of targets || []) {
      if (!target || typeof target.querySelectorAll !== 'function') continue;
      if (typeof target.closest === 'function' && target.closest('.streaming-block')) continue;
      if (typeof target.matches === 'function' && target.matches(actionable)) blocks.add(target);
      target.querySelectorAll(actionable).forEach(block => {
        if (!block.closest('.streaming-block')) blocks.add(block);
      });
    }
    const results = await Promise.all(Array.from(blocks, block => {
      if (!block.isConnected) return false;
      const code = block.querySelector('pre code');
      const source = code ? code.textContent.trim() : '';
      if (!source) return false;
      if (block.dataset.state === 'idle') {
        const cached = diagramCache.get(diagramKey(diagramConfig(), source));
        if (cached === undefined) return false;
        return applyDiagramUpdate(block, () => {
          block.querySelector('.diagram-canvas').innerHTML = cached;
          block.dataset.state = 'ready';
        });
      }
      if (diagramTasks.has(block)) return diagramTasks.get(block);
      const task = (async () => {
        try {
          const svg = await renderDiagramSVG(source);
          return applyDiagramUpdate(block, () => {
            block.querySelector('.diagram-canvas').innerHTML = svg;
            block.dataset.state = 'ready';
          });
        } catch (error) {
          const reason = String(error && error.message || error).split('\n')[0].slice(0, 200);
          return applyDiagramUpdate(block, () => {
            block.querySelector('.diagram-error').textContent = t('diagramError') + reason;
            block.dataset.state = 'error';
          });
        } finally {
          diagramTasks.delete(block);
        }
      })();
      diagramTasks.set(block, task);
      return task;
    }));
    return results.some(Boolean);
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
          html.push(renderCodeBlock(fence.language, fence.lines));
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
    if (fence) html.push(renderCodeBlock(fence.language, fence.lines, false));
    if (math) html.push(`<p>${inlineMarkup(`$$\n${math.join('\n')}`)}</p>`);
    return html.join('');
  }

  function renderSourceLines(language, text) {
    const lines = highlightCodeLines(language, text.replace(/\r\n?/g, '\n'));
    return `<div class="file-source-body">${lines.map((line, index) =>
      `<div class="source-line"><span class="line-number">${index + 1}</span><code>${line}</code></div>`
    ).join('')}</div>`;
  }

  function notebookText(value) {
    return Array.isArray(value) ? value.join('') : String(value == null ? '' : value);
  }

  function renderNotebookOutput(output) {
    output = output && typeof output === 'object' ? output : {};
    if (output.output_type === 'stream') {
      // Progress bars rewrite a line with \r; show only each line's final state.
      const text = notebookText(output.text).replace(/\r\n/g, '\n').split('\n')
        .map(line => line.slice(line.lastIndexOf('\r') + 1)).join('\n');
      return `<pre class="nb-output${output.name === 'stderr' ? ' nb-stderr' : ''}">${escapeHTML(text)}</pre>`;
    }
    if (output.output_type === 'error') {
      const trace = Array.isArray(output.traceback) && output.traceback.length
        ? output.traceback.join('\n')
        : `${output.ename || 'Error'}: ${output.evalue || ''}`;
      return `<pre class="nb-output nb-error">${escapeHTML(cleanTranscriptText(trace))}</pre>`;
    }
    const data = output.data && typeof output.data === 'object' ? output.data : {};
    for (const type of ['image/png', 'image/jpeg', 'image/gif']) {
      const encoded = notebookText(data[type]).replace(/\s+/g, '');
      if (encoded && /^[A-Za-z0-9+/=]+$/.test(encoded)) {
        return `<div class="nb-output nb-image"><img src="data:${type};base64,${encoded}" alt=""></div>`;
      }
    }
    if (data['image/svg+xml']) {
      const svg = encodeURIComponent(notebookText(data['image/svg+xml']));
      return `<div class="nb-output nb-image"><img src="data:image/svg+xml;charset=utf-8,${escapeHTML(svg)}" alt=""></div>`;
    }
    if (data['text/markdown']) {
      return `<div class="nb-output nb-markdown-output">${renderMarkdown(notebookText(data['text/markdown']))}</div>`;
    }
    if (data['text/plain'] != null) return `<pre class="nb-output">${escapeHTML(notebookText(data['text/plain']))}</pre>`;
    return '';
  }

  function renderNotebook(text) {
    let notebook;
    try { notebook = JSON.parse(text); } catch (_) { return ''; }
    if (!notebook || !Array.isArray(notebook.cells)) return '';
    const metadata = notebook.metadata && typeof notebook.metadata === 'object' ? notebook.metadata : {};
    const language = String((metadata.language_info && metadata.language_info.name) ||
      (metadata.kernelspec && metadata.kernelspec.language) || 'python');
    const cells = notebook.cells.map(cell => {
      cell = cell && typeof cell === 'object' ? cell : {};
      const source = notebookText(cell.source);
      if (cell.cell_type === 'markdown') return `<section class="nb-cell nb-markdown">${renderMarkdown(source)}</section>`;
      if (cell.cell_type !== 'code') return `<section class="nb-cell nb-raw"><pre>${escapeHTML(source)}</pre></section>`;
      const count = Number.isInteger(cell.execution_count) ? cell.execution_count : ' ';
      const outputs = (Array.isArray(cell.outputs) ? cell.outputs : []).map(renderNotebookOutput).join('');
      return `<section class="nb-cell nb-code"><div class="nb-prompt">In [${count}]:</div>` +
        `${renderCodeBlock(language, source.split('\n'))}` +
        `${outputs ? `<div class="nb-outputs">${outputs}</div>` : ''}</section>`;
    }).join('');
    return `<div class="file-notebook-body">${cells}</div>`;
  }

  async function renderFilePreview(payload) {
    const document = payload && typeof payload === 'object' ? payload : {};
    const kind = ['markdown', 'image', 'notebook'].includes(document.kind) ? document.kind : 'source';
    const title = String(document.title || '');
    const path = String(document.path || '');
    const text = String(document.text == null ? '' : document.text);
    const header = `<header class="file-document-header"><h1>${escapeHTML(title)}</h1>` +
      `<div class="file-document-path">${escapeHTML(path)}</div></header>`;
    let body = '';
    if (kind === 'markdown') {
      body = `<div class="file-markdown-body">${renderMarkdown(text)}</div>`;
    } else if (kind === 'image') {
      const source = String(document.dataURL || '');
      body = /^data:image\/[\w.+-]+;base64,/.test(source)
        ? `<div class="file-image-body"><img src="${escapeHTML(source)}" alt="${escapeHTML(title)}"></div>`
        : '';
    } else if (kind === 'notebook') {
      body = renderNotebook(text) || renderSourceLines('json', text);
    } else if (['mmd', 'mermaid'].includes(fileLanguage(title))) {
      // A Mermaid file is one diagram block, compiled by hand like those in chat.
      body = `<div class="file-markdown-body">${renderCodeBlock('mermaid', text.replace(/\r\n?/g, '\n').split('\n'))}</div>`;
    } else {
      body = renderSourceLines(fileLanguage(title), text);
    }
    const html = `<article class="file-document ${kind}-document">${header}${body}</article>`;
    const root = rootElement();
    if (!root) return html;
    await typeset([root], mathJax => {
      if (mathJax && typeof mathJax.typesetClear === 'function') mathJax.typesetClear([root]);
      resetVirtualContent(root, mathJax);
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

  function renderTurnEditSummary(messages, session, turnIndex, mounted = false) {
    const files = changedFileSummary(messages);
    if (!files.length) return '';
    if (liveRendering && !mounted) {
      return virtualBlock('edit-summary-slot', record =>
        renderTurnEditSummary(record.summaryMessages, state.session, record.turnIndex, true),
        100 + Math.min(files.length, 3) * 32, ' data-edit-summary', { summaryMessages: messages, turnIndex });
    }
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
      const html = renderLive(() => renderTurnEditSummary(state.renderedTurns[index] || [], session, index));
      if (!html) {
        if (existing) { releaseVirtualContent(existing, scope.MathJax, true); existing.remove(); }
        return;
      }
      const template = scope.document.createElement('template');
      template.innerHTML = html;
      const replacement = template.content.firstElementChild;
      const previous = existing && virtualBodies.get(existing.dataset.virtualBody);
      const record = virtualBodies.get(replacement.dataset.virtualBody);
      if (previous) {
        record.ui = previous.mounted ? captureVirtualUI(existing) : previous.ui;
        record.children = previous.mounted ? rememberVirtualChildren(existing) : previous.children;
      }
      if (existing) { releaseVirtualContent(existing, scope.MathJax, true); existing.replaceWith(replacement); }
      else turn.appendChild(replacement);
      registerVirtualContent(replacement);
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
      const slot = button.closest('[data-virtual-body]');
      const record = slot && virtualBodies.get(slot.dataset.virtualBody);
      bridge.postMessage({
        text: eventText(messageByKey.get(button.dataset.copyKey) || (record && record.message) || {}),
        sessionId: String(state.session && (state.session.sessionId || state.session.id) || '')
      });
    });
  }

  function copyTextFallback(text) {
    const area = scope.document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.cssText = 'position:fixed;top:0;left:0;opacity:0;pointer-events:none';
    scope.document.body.appendChild(area);
    area.select();
    let copied = false;
    try { copied = scope.document.execCommand('copy'); } catch (_) { copied = false; }
    area.remove();
    return copied;
  }

  function installCodeCopyBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && typeof target.closest === 'function'
        ? target.closest('.code-copy-button') : null;
      if (!button) return;
      const block = button.closest('.code-block');
      const code = block && block.querySelector('pre code');
      const text = code ? code.textContent : '';
      if (!text) return;
      const bridge = scope.webkit && scope.webkit.messageHandlers &&
        scope.webkit.messageHandlers.copyAssistantOutput;
      const sessionId = String(state.session && (state.session.sessionId || state.session.id) || '');
      // The file preview web view has no native bridge, so it copies in-page.
      if (bridge && typeof bridge.postMessage === 'function' && sessionId) {
        bridge.postMessage({ text, sessionId, kind: 'code' });
      } else if (!copyTextFallback(text)) {
        return;
      }
      button.classList.add('copied');
      scope.clearTimeout(button.copiedTimer);
      button.copiedTimer = scope.setTimeout(() => button.classList.remove('copied'), 1600);
    });
  }

  // Render compiles one diagram on demand; the toggle flips a rendered diagram
  // between the chart and its Mermaid source.
  function installDiagramToggleBridge() {
    if (!scope || !scope.document) return;
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      if (!target || typeof target.closest !== 'function') return;
      const renderButton = target.closest('.diagram-render');
      const toggleButton = renderButton ? null : target.closest('.diagram-toggle');
      const block = (renderButton || toggleButton || target).closest('.diagram-block');
      if (!block || !(renderButton || toggleButton)) return;
      if (renderButton) {
        const state = block.dataset.state;
        // A streaming message is rebuilt on every update, so wait until it settles.
        if ((state !== 'idle' && state !== 'error') || block.closest('.streaming-block')) return;
        block.dataset.state = 'rendering';
        renderDiagrams([block]).catch(error => scope.console.error(error));
      } else if (block.dataset.view === 'source') {
        delete block.dataset.view;
        refreshDiagramViewport(block);
      } else {
        const canvas = block.querySelector('.diagram-canvas');
        diagramScrollPositions.set(block, { left: canvas.scrollLeft, top: canvas.scrollTop });
        block.dataset.view = 'source';
      }
    });
  }

  function installDiagramZoomBridge() {
    if (!scope || !scope.document) return;
    const diagramAt = target => {
      const element = elementForNode(target);
      const canvas = element && element.closest('.diagram-canvas');
      const block = canvas && canvas.closest('.diagram-block');
      return block && block.dataset.state === 'ready' && block.dataset.view !== 'source' ? block : null;
    };
    scope.document.addEventListener('click', event => {
      const target = elementForNode(event.target);
      const button = target && target.closest('.diagram-zoom-button');
      if (!button) return;
      const block = button.closest('.diagram-block');
      const action = button.dataset.diagramZoom;
      const zoom = Number(block.dataset.zoom) || 1;
      zoomDiagram(block, action === 'reset' ? 1 : zoom * (action === 'in' ? 1.25 : 0.8));
    });
    let gesture = null;
    scope.document.addEventListener('wheel', event => {
      const block = event.ctrlKey && diagramAt(event.target);
      if (!block) return;
      event.preventDefault();
      if (gesture) return;
      const pixels = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? scope.innerHeight : 1);
      zoomDiagram(block, (Number(block.dataset.zoom) || 1) * Math.exp(-pixels / 300), event);
    }, { passive: false });
    scope.document.addEventListener('gesturestart', event => {
      const block = diagramAt(event.target);
      if (!block) return;
      event.preventDefault();
      gesture = { block, zoom: Number(block.dataset.zoom) || 1 };
    }, { passive: false });
    scope.document.addEventListener('gesturechange', event => {
      if (!gesture) return;
      event.preventDefault();
      if (gesture.block.isConnected) zoomDiagram(gesture.block, gesture.zoom * event.scale, event);
    }, { passive: false });
    scope.document.addEventListener('gestureend', event => {
      if (!gesture) return;
      event.preventDefault();
      gesture = null;
    }, { passive: false });
    scope.addEventListener('resize', () => {
      scope.document.querySelectorAll('.diagram-block[data-state="ready"]').forEach(refreshDiagramViewport);
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

  function estimatedEventHeight(message) {
    const kind = eventKind(message);
    if (['tool', 'thinking', 'diff'].includes(kind)) return 58;
    const text = eventText(message);
    const columns = Math.max(1, Math.floor(((scope.innerWidth || 720) - 100) / 8));
    const lines = text.split('\n').reduce((sum, line) => sum + Math.max(1, Math.ceil(line.length / columns)), 0);
    return Math.max(58, lines * 26 + (kind === 'user' ? 26 : 42)) + ((message.images || []).length ? 210 : 0);
  }

  function renderEvent(message, session, mounted = false) {
    message = message || {};
    if (liveRendering && !mounted) {
      return virtualBlock('event-slot', record => renderLive(() => renderEvent(record.message, state.session, true)),
        estimatedEventHeight(message), ` data-message-key="${escapeHTML(message.messageKey || '')}"`, { message });
    }
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
    return `<section class="assistant-output"><div class="assistant-output-toolbar"><button type="button" class="assistant-copy-button" data-copy-key="${escapeHTML(message.messageKey || '')}"><span aria-hidden="true">⧉</span>${escapeHTML(t('copyOutput'))}</button></div>${contentBody('assistant-text', text, () => renderMarkdown(text), ` data-model="${escapeHTML(model)}"${anchorAttribute}`)}</section>`;
  }

  function renderToolGroup(messages, session, mounted = false) {
    const tools = (Array.isArray(messages) ? messages : [])
      .filter(message => eventKind(message || {}) === 'tool');
    if (!tools.length) return '';
    if (liveRendering && !mounted) {
      return virtualBlock('tool-group-slot', record => renderLive(() => renderToolGroup(record.tools, state.session, true)), 58,
        '', { tools });
    }
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
      turns.push(`<section class="turn" data-turn-index="${turns.length}">${current.prompt}<div class="turn-events">${renderEventSequence(current.events, session)}</div>${renderTurnEditSummary(current.events, session, turns.length)}</section>`);
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
    for (const record of virtualBodies.values()) {
      const message = record.message;
      const update = message && message.kind === 'question' && answers.get(message.toolUseId);
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
      releaseVirtualContent(card, scope.MathJax);
      card.replaceWith(replacement);
      typeset([replacement]);
    });
  }

  function refreshVirtualRecord(record, mathJax) {
    if (!record.mounted) {
      if (record.message) {
        record.height = estimatedEventHeight(record.message);
        record.node.style.minHeight = `${record.height}px`;
      }
      return null;
    }
    const slot = record.node;
    record.ui = captureVirtualUI(slot);
    record.children = rememberVirtualChildren(slot);
    releaseVirtualContent(slot, mathJax);
    slot.innerHTML = record.render(record);
    restoreVirtualUI(slot, record.ui);
    restoreVirtualChildren(slot, record.children);
    registerVirtualContent(slot);
    return slot;
  }

  function sameMessageValue(left, right) {
    if (left === right) return true;
    if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
    const keys = Object.keys(left);
    return keys.length === Object.keys(right).length && keys.every(key =>
      Object.prototype.hasOwnProperty.call(right, key) && sameMessageValue(left[key], right[key]));
  }

  function sameEventContent(left, right) {
    const fields = ['role', 'kind', 'type', 'text', 'content', 'output', 'error', 'isError',
      'model', 'toolName', 'name', 'title', 'filePath', 'path', 'oldText', 'newText',
      'images', 'questions', 'toolUseId', 'answered', 'answerText'];
    return fields.every(key => sameMessageValue(left[key], right[key]));
  }

  function renderClaudeStream() {
    const root = rootElement();
    if (!root) return;
    let region = root.querySelector(':scope > .claude-stream');
    if (!state.stream || !sessionMatches(state.stream)) {
      if (region) { releaseVirtualContent(region, scope.MathJax); region.remove(); }
      return;
    }
    applyQuestionUpdates(state.stream.questionUpdates);
    const messages = state.stream.messages.filter(message => !messageByKey.has(message.messageKey));
    const shouldFollow = nearBottom();
    captureViewportAnchor();
    if (!region && messages.length) {
      region = scope.document.createElement('div');
      region.className = 'claude-stream';
    }
    const changedNodes = [];
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
        if (!sameMessageValue(node.__streamMessage, message)) {
          const slot = node.firstElementChild;
          let record = slot && virtualBodies.get(slot.dataset.virtualBody);
          if (record) {
            record.message = message;
            const changed = refreshVirtualRecord(record, scope.MathJax);
            if (changed) changedNodes.push(changed);
          } else {
            node.innerHTML = renderLive(() => renderEvent(message, state.session));
            registerVirtualContent(node);
            changedNodes.push(node);
          }
          node.classList.toggle('streaming-block', Boolean(message.streaming));
          node.__streamMessage = message;
        }
        if (region.children[index] !== node)
          region.insertBefore(node, region.children[index] || null);
      });
      existing.forEach((node, identity) => {
        if (!retained.has(identity)) { releaseVirtualContent(node, scope.MathJax); node.remove(); }
      });
      if (messages.length) {
        const waiting = root.querySelector(':scope > .claude-waiting');
        if (region.parentNode !== root || region.nextSibling !== waiting)
          root.insertBefore(region, waiting);
      }
      else { releaseVirtualContent(region, scope.MathJax); region.remove(); }
    }
    if (changedNodes.length || virtualCandidates.size) typeset(() => changedNodes);
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
      const hasMath = Boolean(mathJax) && typeof mathJax.typesetPromise === 'function';
      const requestedTargets = Array.from(new Set([...Array.from(typeof targets === 'function' ? targets() : targets || []), ...mounted]));
      const connectedTargets = requestedTargets.filter(target =>
        target && (typeof target.isConnected !== 'boolean' || target.isConnected) &&
        !requestedTargets.some(parent => parent !== target && typeof parent.contains === 'function' && parent.contains(target)));
      const scrollBeforeTypeset = scope.scrollY;
      // Diagram completion anchors its own layout update; do not wait for
      // compilation before processing the next transcript or viewport update.
      renderDiagrams(connectedTargets).catch(error => scope.console.error(error));
      if (!hasMath) return;
      if (hasMath && connectedTargets.length) await mathJax.typesetPromise(connectedTargets);
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
    const sameSession = sessionMatches(session);
    if (!sameSession) state.stream = null;
    state.session = Object.assign({}, session, {
      messages: Array.isArray(session && session.messages) ? session.messages.slice() : []
    });
    messageByKey.clear();
    for (const message of state.session.messages) messageByKey.set(message.messageKey, message);
    state.waiting = Boolean(state.session.awaitingReply);
    state.renderedCount = state.session.messages.length;
    if (!root) return renderSession(state.session);
    const snapshot = state.session;
    await typeset([root], mathJax => {
      const shouldFollow = nearBottom();
      const savedUI = new Map();
      if (sameSession) {
        for (const record of virtualBodies.values()) {
          const key = record.message ? `event:${record.message.messageKey}`
            : record.tools && record.tools.length ? `group:${record.tools[0].messageKey}` : null;
          if (!key) continue;
          savedUI.set(key, { ui: record.mounted ? captureVirtualUI(record.node) : record.ui,
            children: record.mounted ? rememberVirtualChildren(record.node) : record.children,
            height: record.mounted ? record.node.getBoundingClientRect().height : record.height });
        }
      }
      if (mathJax && typeof mathJax.typesetClear === 'function') mathJax.typesetClear([root]);
      state.viewportAnchor = null;
      state.pendingQuote = null;
      resetVirtualContent(root, mathJax);
      state.renderedTurns = messageTurns(snapshot.messages);
      root.innerHTML = renderLive(() => renderSession(snapshot));
      registerVirtualContent(root);
      for (const record of virtualBodies.values()) {
        const key = record.message ? `event:${record.message.messageKey}`
          : record.tools && record.tools.length ? `group:${record.tools[0].messageKey}` : null;
        const saved = savedUI.get(key);
        if (!saved) continue;
        record.ui = saved.ui;
        record.children = saved.children;
        record.height = saved.height;
        record.node.style.minHeight = `${saved.height}px`;
      }
      renderClaudeStream();
      if (shouldFollow) scope.scrollTo(0, scope.document.body.scrollHeight);
    });
    captureViewportAnchor();
    return state.renderedCount;
  }

  async function updateClaudeMessages(session, updates) {
    if (!sessionMatches(session)) return null;
    const replacements = new Map((updates || []).map(message => [message.messageKey, message]));
    const metadata = Object.assign({}, session);
    delete metadata.messages;
    state.session = Object.assign({}, state.session, metadata, {
      messages: state.session.messages.map(message => replacements.get(message.messageKey) || message)
    });
    for (const message of replacements.values()) messageByKey.set(message.messageKey, message);
    state.waiting = Boolean(state.session.awaitingReply);
    const root = rootElement();
    if (!root) return state.renderedCount;
    const changedNodes = [];
    await typeset(() => changedNodes, mathJax => {
      const follow = nearBottom();
      captureViewportAnchor();
      state.renderedTurns = messageTurns(state.session.messages);
      const dirtyTurns = new Map();
      // Only top-level cards own message records. Body records are disposable.
      for (const record of Array.from(virtualBodies.values())) {
        if (record.tools) record.tools = record.tools.map(message => replacements.get(message.messageKey) || message);
        const message = record.message && replacements.get(record.message.messageKey);
        if (!message) continue;
        record.message = message;
        const changed = refreshVirtualRecord(record, mathJax);
        if (changed) changedNodes.push(changed);
        if (eventKind(message) === 'diff') {
          const turn = record.node.closest('section.turn');
          if (turn) dirtyTurns.set(turn, Number(turn.dataset.turnIndex));
        }
      }
      refreshTurnEditSummaries(root, state.session, dirtyTurns);
      applyQuestionUpdates(session.questionUpdates);
      renderClaudeStream();
      syncClaudeWaiting(root);
      if (follow) scope.scrollTo(0, scope.document.body.scrollHeight);
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
    for (const message of incoming) messageByKey.set(message.messageKey, message);
    state.waiting = Boolean(state.session.awaitingReply);
    state.renderedCount = state.session.messages.length;
    const root = rootElement();
    if (!root) return renderSession(state.session);
    applyQuestionUpdates(session.questionUpdates);
    if (!incoming.length) {
      syncClaudeWaiting(root);
      return state.renderedCount;
    }

    const snapshot = state.session;
    const addedNodes = [];
    await typeset(() => addedNodes, () => {
      const shouldFollow = nearBottom();
      root.querySelectorAll('.claude-waiting').forEach(node => node.remove());
      const selection = scope.getSelection();
      const selected = selection && !selection.isCollapsed ? {
        anchorNode: selection.anchorNode, anchorOffset: selection.anchorOffset,
        focusNode: selection.focusNode, focusOffset: selection.focusOffset
      } : null;
      const dirtyTurns = new Map();
      const streamCards = new Map();
      const stream = root.querySelector(':scope > .claude-stream');
      if (stream) for (const node of stream.children) {
        const slot = node.firstElementChild;
        const record = slot && virtualBodies.get(slot.dataset.virtualBody);
        if (record && record.message) streamCards.set(record.message.messageKey, record);
      }
      const appendHTML = (parent, html) => {
        const template = scope.document.createElement('template');
        template.innerHTML = html;
        const nodes = Array.from(template.content.childNodes);
        nodes.forEach((node, nodeIndex) => {
          if (node.nodeType === 1) {
            const slots = Array.from(node.querySelectorAll('.event-slot'));
            if (node.classList.contains('event-slot')) slots.unshift(node);
            for (const slot of slots) {
              const fresh = virtualBodies.get(slot.dataset.virtualBody);
              const previous = fresh && fresh.message && streamCards.get(fresh.message.messageKey);
              if (!previous) continue;
              const changed = !sameEventContent(previous.message, fresh.message);
              previous.message = fresh.message;
              if (changed) refreshVirtualRecord(previous, scope.MathJax);
              streamCards.delete(fresh.message.messageKey);
              virtualBodies.delete(fresh.id);
              slot.replaceWith(previous.node);
              if (slot === node) { node = previous.node; nodes[nodeIndex] = node; }
              virtualCandidates.add(previous);
            }
          }
          parent.appendChild(node);
          if (node.nodeType === 1) registerVirtualContent(node);
        });
        addedNodes.push(...nodes.filter(node => node.nodeType === 1));
        return nodes.find(node => node.nodeType === 1) || null;
      };
      const emptyTurn = () => appendHTML(root,
        `<section class="turn" data-turn-index="${state.renderedTurns.length}"><header class="turn-header"><span class="turn-label">TURN</span></header><div class="turn-events"></div></section>`);
      const appendToolMessage = (events, message) => {
        const previous = events.lastElementChild;
        const record = previous && virtualBodies.get(previous.dataset.virtualBody);
        if (!record || !record.tools) {
          appendHTML(events, renderLive(() => renderToolGroup([message], snapshot)));
          return;
        }
        record.tools.push(message);
        if (!record.mounted) return;
        const group = previous.querySelector('.tool-group');
        const toolEvents = group.querySelector(':scope > .tool-group-events');
        appendHTML(toolEvents, renderLive(() => renderEvent(message, snapshot)));
        group.dataset.toolCount = String(record.tools.length);
        group.querySelector(':scope > summary .tool-group-count').textContent = t('toolCount', { count: record.tools.length });
      };

      incoming.forEach(message => {
        if (eventKind(message) === 'user') {
          state.renderedTurns.push([]);
          appendHTML(root,
            `<section class="turn" data-turn-index="${state.renderedTurns.length - 1}"><header class="turn-header"><span class="turn-label">TURN</span>${renderLive(() => renderEvent(message, snapshot))}</header><div class="turn-events"></div></section>`);
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
      if (selected && selected.anchorNode.isConnected && selected.focusNode.isConnected) {
        selection.setBaseAndExtent(selected.anchorNode, selected.anchorOffset, selected.focusNode, selected.focusOffset);
      }
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
  installCodeCopyBridge();
  installDiagramToggleBridge();
  installDiagramZoomBridge();
  installMessageImageBridge();
  installQuestionCardBridge();
  installStableViewport();
  installJumpToBottom();
  installVirtualContent();

  return {
    cleanTranscriptText,
    inlineMarkup,
    renderMarkdown,
    renderDiagrams,
    createDiagramCache,
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
    updateClaudeMessages,
    sessionMatches
  };
});
