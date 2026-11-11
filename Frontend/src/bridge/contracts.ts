export type Surface = 'main' | 'floating';
export type ThemeAppearance = 'light' | 'dark';
export type UILanguage = 'zh-Hans' | 'en';
export type WorkingTabKind = 'overview' | 'file' | 'review' | 'tasks';
export type SidebarGroupMode = 'time' | 'project';

export interface ModelOption {
  badge?: string;
  id: string;
  label: string;
  multiplier?: string;
  shortLabel?: string;
}

export interface UsageQuotaState {
  available: boolean;
  error?: string;
  fiveHourPercent: number;
  fiveHourResetText: string;
  sevenDayPercent: number;
  sevenDayResetText: string;
}

export interface WindowStateSnapshot {
  appearance?: ThemeAppearance;
  claudeSettings?: {
    availableModels?: ModelOption[];
    effortLevels?: string[];
    permissionModes?: Array<{ id: string; label: string; wireMode: string }>;
    selectedEffort?: string;
    selectedModel?: string;
    selectedPermissionMode?: string;
    sessionId?: string;
  };
  defaultCwd?: string;
  hostName?: string;
  language?: UILanguage;
  platformInfo?: string;
  statusBanner?: string;
  surface?: Surface;
  usage?: UsageQuotaState;
  version?: string;
}

export interface PendingImageItem {
  dataUrl?: string;
  id?: string;
  name: string;
  path: string;
  temporary?: boolean;
}

export interface WorkspaceTabItem {
  activeToolPageKind: '' | WorkingTabKind;
  connecting: boolean;
  cwd: string;
  fileToolPageOpen: boolean;
  fileTreeRootPath: string;
  id: string;
  overviewExpanded: boolean;
  panelExpanded: boolean;
  responding: boolean;
  reviewToolPageOpen: boolean;
  running: boolean;
  sessionId: string;
  status: string;
  title: string;
}

export interface ComposerSnapshot {
  draft: string;
  id: string;
  pendingFiles: string[];
  pendingImages: PendingImageItem[];
  sessionId: string;
}

export interface WorkspaceSnapshot {
  activeTabId: string;
  floatingSessionId: string;
  floatingVisible: boolean;
  selectedSessionId: string;
  tabs: WorkspaceTabItem[];
}

export interface ChangedFileSummary {
  added: number;
  changeCount?: number;
  displayName: string;
  filePath: string;
  removed: number;
}

export interface SessionTaskItem {
  activeForm?: string;
  description?: string;
  id: string;
  status: 'pending' | 'in_progress' | 'completed' | string;
  subject: string;
}

export interface ClaudeProcessTask {
  description?: string;
  run_id?: string;
  task_id: string;
  task_type: string;
  tool_use_id?: string;
}

export interface ClaudeTasksSnapshot {
  background: ClaudeProcessTask[];
  foreground: ClaudeProcessTask[];
  generation: string;
  sessionId: string;
}

export interface ContextCategoryItem {
  category: string;
  label?: string;
  percentage?: number;
  tokens: number;
}

export interface SessionSummary {
  accessedDirectories?: string[];
  apiCostAvailable?: boolean;
  apiEquivalentCostUSD?: number;
  awaitingReply?: boolean;
  changedFiles?: ChangedFileSummary[];
  codeLinesAdded?: number;
  codeLinesRemoved?: number;
  connected?: boolean;
  contextBreakdown?: ContextCategoryItem[];
  contextUsed?: number;
  contextWindow?: number;
  cwd: string;
  effort?: string;
  filePath: string;
  model?: string;
  modelUsageBreakdown?: Record<
    string,
    {
      cacheRead: number;
      cacheReadCost?: number;
      cacheWrite: number;
      cacheWriteCost?: number;
      cost?: number;
      input: number;
      inputCost?: number;
      output: number;
      outputCost?: number;
    }
  >;
  modifiedAtMs: number;
  projectKey: string;
  projectTitle: string;
  responding?: boolean;
  running?: boolean;
  sessionId: string;
  tasks?: SessionTaskItem[];
  title: string;
  turnCount?: number;
}

export interface PrettyTermImageAttachment {
  dataUrl?: string;
  mediaType?: string;
  name?: string;
  path?: string;
}

export interface QuestionOptionItem {
  description?: string;
  label: string;
}

export interface AskUserQuestionItem {
  header?: string;
  multiSelect?: boolean;
  options?: QuestionOptionItem[];
  question: string;
}

export interface PrettyTermMessage {
  added?: number;
  answerText?: string;
  answered?: boolean;
  command?: string;
  filePath?: string;
  images?: PrettyTermImageAttachment[];
  isError?: boolean;
  kind?: 'thinking' | 'tool' | 'diff' | 'error' | 'question' | string;
  messageKey?: string;
  model?: string;
  newText?: string;
  oldText?: string;
  questions?: AskUserQuestionItem[];
  removed?: number;
  role: 'user' | 'assistant' | 'tool' | 'system' | string;
  startLine?: number;
  streamID?: string;
  streaming?: boolean;
  text?: string;
  timestamp?: string;
  toolInput?: Record<string, unknown>;
  toolName?: string;
  toolUseId?: string;
  usage?: { costUSD?: number; outputTokens?: number; totalTokens?: number; usageId?: string };
  [key: string]: unknown;
}

export interface TranscriptMetadata {
  awaitingReply?: boolean;
  cwd?: string;
  interfaceLanguage?: string;
  messages?: PrettyTermMessage[];
  model?: string;
  questionUpdates?: Array<{ answerText?: string; answered?: boolean; toolUseId: string }>;
  sessionId: string;
  title?: string;
}

export interface StreamPayload {
  active: boolean;
  generation?: string;
  compacting?: boolean;
  messages: PrettyTermMessage[];
  questionUpdates?: Array<{ answerText?: string; answered?: boolean; toolUseId: string }>;
  revision?: number;
  sessionId: string;
}

export interface SlashCommandItem {
  description?: string;
  icon?: string;
  name: string;
  title?: string;
}

export interface FileTreeNode {
  isDirectory: boolean;
  name: string;
  path: string;
  size?: number;
}

export interface FilePreviewPayload {
  content?: string;
  dataUrl?: string;
  error?: string;
  html?: string;
  kind: string;
  language?: string;
  name?: string;
  path: string;
  size?: number;
}

export interface GitReviewFile {
  added: number;
  binary: boolean;
  patch: string;
  path: string;
  removed: number;
  statusCode: string;
  statusLabel: string;
}

export interface GitStateSnapshot {
  actionInFlight?: boolean;
  actionStatus?: string;
  branch?: string;
  directories?: string[];
  editEvents?: Array<{
    added?: number;
    filePath: string;
    newText: string;
    oldText: string;
    removed?: number;
    toolName?: string;
  }>;
  error?: string;
  files?: GitReviewFile[];
  loading?: boolean;
  observedDirectory?: string;
  reviewMode?: 'git' | 'turn';
  turnIndex?: number;
}

export interface TerminalOutputState {
  runId?: string;
  sequence?: number;
  reset?: boolean;
  command?: string;
  cwd: string;
  exitCode?: number | null;
  output: string;
  running: boolean;
  tabId: string;
}

export interface NativeUIBridgeReply<T = unknown> {
  action?: string;
  data?: T;
  error?: string;
  ok: boolean;
}
