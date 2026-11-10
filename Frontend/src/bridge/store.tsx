import { useCallback, useState, useSyncExternalStore, type Dispatch, type SetStateAction } from 'react';

import type {
  ClaudeTasksSnapshot,
  ComposerSnapshot,
  FilePreviewPayload,
  FileTreeNode,
  GitStateSnapshot,
  PrettyTermMessage,
  SessionSummary,
  SidebarGroupMode,
  SlashCommandItem,
  StreamPayload,
  TerminalOutputState,
  TranscriptMetadata,
  UILanguage,
  WindowStateSnapshot,
  WorkspaceSnapshot,
} from './contracts';
import { invokeNativeUI, normalizeAppearance, normalizeLanguage, normalizeSurface, readInitialWindowState } from './native';
import { TranscriptProjection, type TranscriptState } from './transcript';

interface BridgeWindow extends Window {
  __ptSessionMatches?: (arg: TranscriptMetadata | string) => boolean;
  appendClaudeMessages?: (arg: TranscriptMetadata | string, messages: PrettyTermMessage[]) => Promise<void>;
  setClaudeSession?: (arg: TranscriptMetadata | string, messages?: PrettyTermMessage[]) => Promise<void>;
  setClaudeStream?: (snapshot: StreamPayload) => void;
  setClaudeWaiting?: (waiting: boolean) => void;
  setPrettyTermClaudeTasks?: (snapshot: ClaudeTasksSnapshot) => void;
  setPrettyTermComposer?: (snapshot: ComposerSnapshot) => void;
  setPrettyTermCommandResults?: (payload: {
    commandOutput?: string;
    items: SlashCommandItem[];
    query?: string;
    tabId?: string;
  }) => void;
  setPrettyTermFilePreview?: (payload: {
    error?: string;
    path: string;
    payload?: FilePreviewPayload | null;
    sessionId?: string;
    tabId: string;
    requestId: string;
    loading?: boolean;
  }) => void;
  setPrettyTermFileTree?: (payload: {
    children: FileTreeNode[];
    error?: string;
    path: string;
    rootPath: string;
    tabId: string;
  }) => void;
  setPrettyTermGitState?: (snapshot: GitStateSnapshot) => void;
  setPrettyTermLanguage?: (lang: string) => void;
  setPrettyTermSessions?: (sessions: SessionSummary[]) => void;
  setPrettyTermTerminalOutput?: (payload: TerminalOutputState) => void;
  setPrettyTermTheme?: (theme: { appearance?: string } | string) => void;
  setPrettyTermUsage?: (usage: WindowStateSnapshot['usage']) => void;
  setPrettyTermClaudeSettings?: (settings: WindowStateSnapshot['claudeSettings']) => void;
  setPrettyTermStatus?: (status: string) => void;
  setPrettyTermWindowState?: (snapshot: WindowStateSnapshot) => void;
  setPrettyTermWorkspace?: (snapshot: WorkspaceSnapshot) => void;
  updateClaudeMessages?: (arg: TranscriptMetadata | string, updates: PrettyTermMessage[]) => Promise<void>;
}

export interface AppStoreValue {
  activeSession: SessionSummary | null;
  claudeSettings: WindowStateSnapshot['claudeSettings'];
  claudeTasks: ClaudeTasksSnapshot;
  usage: WindowStateSnapshot['usage'];
  status: string;
  activeTab: WorkspaceSnapshot['tabs'][number] | null;
  commandResults: { commandOutput?: string; items: SlashCommandItem[]; query: string };
  filePreview: { error?: string; loading: boolean; path: string; payload: FilePreviewPayload | null; requestId: string };
  fileTreeByPath: Record<string, FileTreeNode[]>;
  gitState: GitStateSnapshot;
  groupMode: SidebarGroupMode;
  language: UILanguage;
  renameModalSession: SessionSummary | null;
  turnIds: readonly string[];
  searchQuery: string;
  selectedSessionId: string;
  sessions: SessionSummary[];
  setGroupMode: (mode: SidebarGroupMode) => void;
  setRenameModalSession: (session: SessionSummary | null) => void;
  setSearchQuery: (q: string) => void;
  setSidebarCollapsed: (collapsed: boolean | ((v: boolean) => boolean)) => void;
  setTerminalOpen: (open: boolean | ((v: boolean) => boolean)) => void;
  sidebarCollapsed: boolean;
  terminalOpen: boolean;
  terminalState: TerminalOutputState;
  transcript: TranscriptState;
  windowState: WindowStateSnapshot;
  workspace: WorkspaceSnapshot;
  composer: ComposerSnapshot;
  composerQuote: string;
  setComposerQuote: Dispatch<SetStateAction<string>>;
}

const DEFAULT_WORKSPACE: WorkspaceSnapshot = {
  activeTabId: '',
  floatingSessionId: '',
  floatingVisible: false,
  selectedSessionId: '',
  tabs: [],
};

type Listener = () => void;

const projection = new TranscriptProjection(normalizeLanguage(readInitialWindowState().language));
const listeners = new Map<keyof AppStoreValue, Set<Listener>>();
const rowListeners = new Map<string, Set<Listener>>();

function subscribe<K>(map: Map<K, Set<Listener>>, key: K, listener: Listener) {
  let group = map.get(key);
  if (!group) map.set(key, (group = new Set()));
  group.add(listener);
  return () => {
    group.delete(listener);
    if (!group.size) map.delete(key);
  };
}

function publish<K extends keyof AppStoreValue>(key: K, value: AppStoreValue[K]) {
  if (Object.is(state[key], value)) return;
  state[key] = value;
  for (const listener of listeners.get(key) ?? []) listener();
}

function setter<K extends keyof AppStoreValue>(key: K): Dispatch<SetStateAction<AppStoreValue[K]>> {
  return (value) => {
    const next = typeof value === 'function'
      ? (value as (previous: AppStoreValue[K]) => AppStoreValue[K])(state[key])
      : value;
    publish(key, next);
  };
}

const initialWindow = readInitialWindowState();
const emptyPreview: AppStoreValue['filePreview'] = { loading: false, path: '', payload: null, requestId: '' };
const emptyTree: Record<string, FileTreeNode[]> = {};
const previews = new Map<string, AppStoreValue['filePreview']>();
const trees = new Map<string, { rootPath: string; children: Record<string, FileTreeNode[]> }>();
const terminalListeners = new Set<(text: string, reset: boolean) => void>();
const composerQuotes = new Map<string, string>();
export const composerEditorId = (tabId: string, sessionId: string) => JSON.stringify([tabId, sessionId]);

function currentEditorId() {
  const sessionId = state.selectedSessionId;
  const tabId = state.windowState.surface === 'floating' ? sessionId : state.workspace.activeTabId;
  return composerEditorId(tabId, sessionId);
}

export function clearSubmittedQuote(editorId: string, quote: string) {
  if (composerQuotes.get(editorId) !== quote) return;
  composerQuotes.delete(editorId);
  if (currentEditorId() === editorId) publish('composerQuote', '');
}

export function observeTerminalOutput(listener: (text: string, reset: boolean) => void) {
  terminalListeners.add(listener);
  return () => { terminalListeners.delete(listener); };
}

const state: AppStoreValue = {
  activeSession: null,
  activeTab: null,
  claudeSettings: initialWindow.claudeSettings,
  claudeTasks: { background: [], foreground: [], generation: '', sessionId: '' },
  usage: initialWindow.usage,
  status: initialWindow.statusBanner ?? '',
  commandResults: { items: [], query: '' },
  composer: { draft: '', id: '', pendingFiles: [], pendingImages: [], sessionId: '' },
  composerQuote: '',
  filePreview: emptyPreview,
  fileTreeByPath: {},
  gitState: { directories: [], files: [], reviewMode: 'git' },
  groupMode: 'time',
  language: normalizeLanguage(initialWindow.language),
  renameModalSession: null,
  turnIds: projection.rowIds,
  searchQuery: '',
  selectedSessionId: '',
  sessions: [],
  setComposerQuote: (value) => {
    const editorId = currentEditorId();
    const next = typeof value === 'function' ? value(state.composerQuote) : value;
    if (next) composerQuotes.set(editorId, next);
    else composerQuotes.delete(editorId);
    publish('composerQuote', next);
  },
  setGroupMode: setter('groupMode'),
  setRenameModalSession: setter('renameModalSession'),
  setSearchQuery: setter('searchQuery'),
  setSidebarCollapsed: setter('sidebarCollapsed'),
  setTerminalOpen: setter('terminalOpen'),
  sidebarCollapsed: false,
  terminalOpen: false,
  terminalState: { cwd: '', output: '', running: false, tabId: '' },
  transcript: projection.state,
  windowState: initialWindow,
  workspace: DEFAULT_WORKSPACE,
};

const rowState = new Map<string, Map<string, unknown>>();
export interface ScrollAnchor { id: string; offset: number; atBottom: boolean }
export const scrollAnchors = new Map<string, ScrollAnchor>();

export function useTurnState<T>(sessionId: string, key: string, initial: T) {
  const [value, setValue] = useState(() => (rowState.get(sessionId)?.get(key) as T | undefined) ?? initial);
  const update: Dispatch<SetStateAction<T>> = (action) => {
    const previous = (rowState.get(sessionId)?.get(key) as T | undefined) ?? value;
    const next = typeof action === 'function' ? (action as (prev: T) => T)(previous) : action;
    let saved = rowState.get(sessionId);
    if (!saved) rowState.set(sessionId, (saved = new Map()));
    saved.set(key, next);
    setValue(next);
  };
  return [value, update] as const;
}

function syncProjection(change: () => void) {
  const previous = new Map([...rowListeners.keys()].map((id) => [id, projection.row(id)]));
  const previousSession = projection.state.sessionId;
  change();
  publish('transcript', projection.state);
  publish('turnIds', projection.rowIds);
  for (const [id, listeners] of rowListeners) {
    if (previous.get(id) === projection.row(id)) continue;
    for (const listener of listeners) listener();
  }
  if (previousSession !== projection.state.sessionId) syncSelection();
}

function syncSelection() {
  const workspace = state.workspace;
  const floating = state.windowState.surface === 'floating';
  const tab = workspace.tabs.find((item) => item.id === workspace.activeTabId) ?? null;
  const sessionId = workspace === DEFAULT_WORKSPACE
    ? state.transcript.sessionId
    : (floating ? workspace.floatingSessionId : workspace.selectedSessionId || tab?.sessionId) || '';
  publish('activeTab', tab);
  publish('selectedSessionId', sessionId);
  publish('composerQuote', composerQuotes.get(currentEditorId()) ?? '');
  publish('activeSession', state.sessions.find((session) => session.sessionId === sessionId) ?? null);
  publish('filePreview', previews.get(workspace.activeTabId) ?? emptyPreview);
  publish('fileTreeByPath', trees.get(workspace.activeTabId)?.children ?? emptyTree);
}

function asMetadata(arg: TranscriptMetadata | string): TranscriptMetadata {
  return typeof arg === 'string' ? { sessionId: arg } : arg;
}

let pendingStream: StreamPayload | undefined;
let frame = 0;

function flushStream() {
  if (frame) cancelAnimationFrame(frame);
  frame = 0;
  const snapshot = pendingStream;
  pendingStream = undefined;
  if (snapshot) syncProjection(() => projection.stream(snapshot));
}

export function installFrontendBridge() {
  const win = window as BridgeWindow;
  win.setPrettyTermWindowState = (snapshot) => {
    const next = { ...state.windowState, ...snapshot };
    next.appearance = normalizeAppearance(next.appearance);
    next.language = normalizeLanguage(next.language);
    next.surface = normalizeSurface(next.surface);
    publish('windowState', next);
    publish('language', next.language);
    syncProjection(() => projection.setLanguage(next.language!));
  };
  win.setPrettyTermUsage = (usage) => publish('usage', usage);
  win.setPrettyTermClaudeTasks = (tasks) => publish('claudeTasks', tasks);
  win.setPrettyTermClaudeSettings = (settings) => publish('claudeSettings', settings);
  win.setPrettyTermStatus = (status) => publish('status', status);
  win.setPrettyTermTheme = (theme) => win.setPrettyTermWindowState?.({ appearance: normalizeAppearance(theme) });
  win.setPrettyTermLanguage = (lang) => win.setPrettyTermWindowState?.({ language: normalizeLanguage(lang) });
  win.setPrettyTermWorkspace = (snapshot) => {
    const retained = new Set(snapshot.tabs.map((tab) => tab.sessionId));
    if (snapshot.floatingSessionId) retained.add(snapshot.floatingSessionId);
    for (const id of rowState.keys()) if (!retained.has(id)) rowState.delete(id);
    for (const id of scrollAnchors.keys()) if (!retained.has(id)) scrollAnchors.delete(id);
    const previousTabs = new Map(state.workspace.tabs.map((tab) => [tab.id, tab]));
    const nextTabs = new Map(snapshot.tabs.map((tab) => [tab.id, tab]));
    for (const [id, old] of previousTabs) {
      const next = nextTabs.get(id);
      if (!next || next.sessionId !== old.sessionId || next.fileTreeRootPath !== old.fileTreeRootPath) {
        previews.delete(id);
        trees.delete(id);
      }
      if (!next || next.sessionId !== old.sessionId) {
        composerQuotes.delete(composerEditorId(id, old.sessionId));
      }
    }
    publish('workspace', snapshot);
    syncSelection();
  };
  win.setPrettyTermComposer = (composer) => publish('composer', composer);
  win.setPrettyTermSessions = (sessions) => {
    publish('sessions', sessions);
    syncSelection();
  };
  win.setPrettyTermGitState = (snapshot) => publish('gitState', snapshot);
  win.setPrettyTermFileTree = ({ path, children, tabId, rootPath }) => {
    const tab = state.workspace.tabs.find((item) => item.id === tabId);
    if (!path || !tab) return;
    const session = state.sessions.find((item) => item.sessionId === tab.sessionId);
    const expectedRoot = tab.fileTreeRootPath || session?.cwd || state.windowState.defaultCwd;
    if (rootPath !== expectedRoot) return;
    const previous = trees.get(tabId);
    const entries = { ...(previous?.rootPath === rootPath ? previous.children : {}), [path]: children };
    trees.set(tabId, { rootPath, children: entries });
    if (tabId === state.workspace.activeTabId) publish('fileTreeByPath', entries);
  };
  win.setPrettyTermFilePreview = (preview) => {
    if (!state.workspace.tabs.some((tab) => tab.id === preview.tabId && tab.sessionId === preview.sessionId)) return;
    const previous = previews.get(preview.tabId);
    if (!preview.loading && previous?.requestId !== preview.requestId) return;
    const next = {
      error: preview.error,
      loading: Boolean(preview.loading),
      path: preview.path,
      payload: preview.payload ?? null,
      requestId: preview.requestId,
    };
    previews.set(preview.tabId, next);
    if (preview.tabId === state.workspace.activeTabId) publish('filePreview', next);
  };
  win.setPrettyTermCommandResults = (payload) => publish('commandResults', {
    commandOutput: payload.commandOutput,
    items: payload.items ?? [],
    query: payload.query ?? '',
  });
  win.setPrettyTermTerminalOutput = (payload) => {
    const previous = state.terminalState;
    if (payload.runId === previous.runId && (payload.sequence ?? 0) <= (previous.sequence ?? -1)) return;
    publish('terminalState', { ...payload, output: '' });
    for (const listener of terminalListeners) listener(payload.output, Boolean(payload.reset));
  };
  win.__ptSessionMatches = (arg) => asMetadata(arg).sessionId === projection.state.sessionId;
  win.setClaudeSession = async (arg, messages) => {
    flushStream();
    const meta = asMetadata(arg);
    syncProjection(() => projection.replace(messages ? { ...meta, messages } : meta));
  };
  win.appendClaudeMessages = async (arg, messages) => {
    syncProjection(() => projection.append(asMetadata(arg), messages));
  };
  win.updateClaudeMessages = async (arg, messages) => {
    syncProjection(() => projection.patch(asMetadata(arg), messages));
  };
  win.setClaudeWaiting = (waiting) => syncProjection(() => projection.setWaiting(Boolean(waiting)));
  win.setClaudeStream = (snapshot) => {
    if (snapshot.sessionId !== projection.state.sessionId) return;
    if (pendingStream && pendingStream.generation === snapshot.generation &&
        snapshot.revision !== undefined && snapshot.revision < (pendingStream.revision ?? -1)) return;
    pendingStream = snapshot;
    if (!snapshot.active) flushStream();
    else if (!frame) frame = requestAnimationFrame(flushStream);
  };
  void invokeNativeUI('frontendReady');
}

export function usePTSlice<K extends keyof AppStoreValue>(key: K): AppStoreValue[K] {
  const listen = useCallback((listener: Listener) => subscribe(listeners, key, listener), [key]);
  const snapshot = useCallback(() => state[key], [key]);
  return useSyncExternalStore(listen, snapshot);
}

export function useTranscriptTurn(id: string) {
  const listen = useCallback((listener: Listener) => subscribe(rowListeners, id, listener), [id]);
  const snapshot = useCallback(() => projection.row(id), [id]);
  return useSyncExternalStore(listen, snapshot);
}

export function transcriptTurn(id: string) {
  return projection.row(id);
}
