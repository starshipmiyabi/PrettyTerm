import type {
  AskUserQuestionItem,
  PrettyTermImageAttachment,
  PrettyTermMessage,
  StreamPayload,
  TranscriptMetadata,
  UILanguage,
} from './contracts';

export interface WorkflowStep {
  filePath?: string;
  id: string;
  inputText?: string;
  isError?: boolean;
  kind: 'thinking' | 'tool' | 'diff' | 'error';
  newText?: string;
  oldText?: string;
  resultText?: string;
  status: 'running' | 'success' | 'error';
  streaming?: boolean;
  subtitle?: string;
  timestamp?: string;
  title: string;
  toolInput?: Record<string, unknown>;
  toolName?: string;
  toolUseId?: string;
}

export interface TurnEditedFile {
  added: number;
  filePath: string;
  newText: string;
  oldText: string;
  removed: number;
  status: 'modified' | 'added';
}

export interface QuestionBlock {
  answerText: string;
  answered: boolean;
  id: string;
  questions: AskUserQuestionItem[];
  toolUseId: string;
}

export interface RenderedUserTurn {
  id: string;
  images: PrettyTermImageAttachment[];
  kind: 'user';
  text: string;
  timestamp?: string;
  turnIndex: number;
}

export interface RenderedAssistantTurn {
  answerBlocks: Array<{ id: string; streaming: boolean; text: string }>;
  editedFiles: TurnEditedFile[];
  hasStreaming: boolean;
  id: string;
  kind: 'assistant';
  model: string;
  questionBlocks: QuestionBlock[];
  steps: WorkflowStep[];
  timeline: AssistantTimelineItem[];
  timestamp?: string;
  turnIndex: number;
  usage?: { costUSD?: number; outputTokens?: number; totalTokens?: number };
  waitingPlaceholder?: boolean;
}

export type AssistantTimelineItem =
  | { answer: RenderedAssistantTurn['answerBlocks'][number]; kind: 'answer' }
  | { kind: 'question'; question: QuestionBlock }
  | { kind: 'step'; step: WorkflowStep };

export type GroupedAssistantTimelineItem =
  | { answer: RenderedAssistantTurn['answerBlocks'][number]; kind: 'answer' }
  | { kind: 'question'; question: QuestionBlock }
  | { id: string; kind: 'stepGroup'; steps: WorkflowStep[] };

export function groupAssistantTimeline(
  timeline: readonly AssistantTimelineItem[],
): GroupedAssistantTimelineItem[] {
  const grouped: GroupedAssistantTimelineItem[] = [];
  let pendingSteps: WorkflowStep[] = [];
  const flushSteps = () => {
    if (pendingSteps.length === 0) return;
    grouped.push({ id: pendingSteps[0].id, kind: 'stepGroup', steps: pendingSteps });
    pendingSteps = [];
  };

  for (const item of timeline) {
    if (item.kind === 'step') {
      pendingSteps.push(item.step);
    } else {
      flushSteps();
      grouped.push(item);
    }
  }
  flushSteps();
  return grouped;
}

export type RenderedTurn = RenderedUserTurn | RenderedAssistantTurn;

export interface TranscriptState {
  awaitingReply: boolean;
  compacting: boolean;
  cwd: string;
  model: string;
  sessionId: string;
  streamActive: boolean;
  title: string;
}

type QuestionState = { answerText: string; answered: boolean };

const emptyTranscript = (): TranscriptState => ({
  awaitingReply: false,
  compacting: false,
  cwd: '',
  model: 'Claude',
  sessionId: '',
  streamActive: false,
  title: '',
});

function basename(filePath: string): string {
  const idx = filePath.lastIndexOf('/');
  return idx >= 0 ? filePath.slice(idx + 1) : filePath;
}

function quickLineDiffCounts(oldText = '', newText = ''): { added: number; removed: number } {
  const oldLines = oldText ? oldText.split('\n') : [];
  const newLines = newText ? newText.split('\n') : [];
  const oldSet = new Set(oldLines);
  const newSet = new Set(newLines);
  let added = 0;
  let removed = 0;
  for (const l of newLines) if (!oldSet.has(l)) added++;
  for (const l of oldLines) if (!newSet.has(l)) removed++;
  return { added, removed };
}

function formatStepSummary(
  msg: PrettyTermMessage,
  language: UILanguage,
): { subtitle?: string; title: string } {
  if (msg.kind === 'thinking') {
    return {
      title: language === 'en' ? 'Reasoning' : '已深度思考',
    };
  }
  const name = msg.toolName || (language === 'en' ? 'Tool Call' : '工具调用');
  const inp = (msg.toolInput ?? {}) as Record<string, unknown>;
  const filePath =
    msg.filePath ||
    (typeof inp.file_path === 'string' && inp.file_path) ||
    (typeof inp.filePath === 'string' && inp.filePath) ||
    (typeof inp.path === 'string' && inp.path) ||
    '';
  const cmd =
    (typeof inp.command === 'string' && inp.command) ||
    (typeof inp.cmd === 'string' && inp.cmd) ||
    '';
  const pattern =
    (typeof inp.pattern === 'string' && inp.pattern) ||
    (typeof inp.query === 'string' && inp.query) ||
    (typeof inp.q === 'string' && inp.q) ||
    '';

  if (name === 'Read' || name === 'read_file' || name === 'view_file') {
    return {
      subtitle: filePath || undefined,
      title: language === 'en' ? `Read ${basename(filePath)}` : `读取文件内容 ${basename(filePath)}`,
    };
  }
  if (name === 'Edit' || name === 'Write' || name === 'MultiEdit') {
    const counts = typeof msg.added === 'number' && typeof msg.removed === 'number'
      ? ` (+${msg.added} -${msg.removed})`
      : '';
    return {
      subtitle: filePath || undefined,
      title:
        language === 'en'
          ? `${name} ${basename(filePath)}${counts}`
          : `${name === 'Write' ? '写入文件' : '修改文件'} ${basename(filePath)}${counts}`,
    };
  }
  if (name === 'Bash' || name === 'run_command') {
    const desc = typeof inp.description === 'string' ? inp.description : '';
    const snippet = desc || cmd.split('\n')[0]?.slice(0, 64) || '';
    return {
      subtitle: snippet || undefined,
      title: language === 'en' ? `Run ${snippet || 'command'}` : `运行命令 ${snippet}`,
    };
  }
  if (name === 'Glob' || name === 'Grep' || name === 'find_by_name' || name === 'grep_search') {
    return {
      subtitle: filePath || pattern || undefined,
      title: language === 'en' ? `Search ${pattern || basename(filePath)}` : `检索 ${pattern || basename(filePath)}`,
    };
  }
  const shortDetail = filePath ? basename(filePath) : pattern || cmd.slice(0, 48);
  return {
    subtitle: filePath || undefined,
    title: shortDetail ? `${name} · ${shortDetail}` : name,
  };
}

function isToolResult(msg: PrettyTermMessage): boolean {
  return msg.role === 'tool' && !!msg.toolUseId &&
    (msg.toolName === '工具结果' || msg.toolName === '工具执行失败' || msg.kind === 'error');
}

const diffCounts = new WeakMap<PrettyTermMessage, { added: number; removed: number }>();

function projectAssistant(
  id: string,
  turnIndex: number,
  records: readonly PrettyTermMessage[],
  model: string,
  questions: ReadonlyMap<string, QuestionState>,
  language: UILanguage,
  active: boolean,
): RenderedAssistantTurn {
  const group: RenderedAssistantTurn = {
    answerBlocks: [],
    editedFiles: [],
    hasStreaming: active,
    id,
    kind: 'assistant',
    model: model || 'Claude',
    questionBlocks: [],
    steps: [],
    timeline: [],
    turnIndex,
    waitingPlaceholder: active && records.length === 0,
  };
  const steps = new Map<string, WorkflowStep>();
  const editedFiles = new Map<string, TurnEditedFile>();

  for (let i = 0; i < records.length; i++) {
    const msg = records[i];
    if (msg.model) group.model = msg.model;
    if (msg.timestamp && !group.timestamp) group.timestamp = msg.timestamp;
    if (msg.streaming) group.hasStreaming = true;
    if (msg.usage) {
      group.usage = {
        costUSD: (group.usage?.costUSD ?? 0) + (msg.usage.costUSD ?? 0),
        outputTokens: Math.max(group.usage?.outputTokens ?? 0, msg.usage.outputTokens ?? 0),
        totalTokens: msg.usage.totalTokens ?? group.usage?.totalTokens,
      };
    }

    // Question card
    if (msg.kind === 'question' && msg.toolUseId) {
      const upd = questions.get(msg.toolUseId);
      const question: QuestionBlock = {
        answerText: upd?.answerText ?? msg.answerText ?? '',
        answered: upd?.answered ?? Boolean(msg.answered),
        id: msg.messageKey || `q-${msg.toolUseId}`,
        questions: msg.questions ?? [],
        toolUseId: msg.toolUseId,
      };
      group.questionBlocks.push(question);
      group.timeline.push({ kind: 'question', question });
      continue;
    }

    // Thinking step
    if (msg.kind === 'thinking') {
      const { title } = formatStepSummary(msg, language);
      const step: WorkflowStep = {
        id: msg.streamID || msg.messageKey || `thinking-${i}`,
        inputText: msg.text || '',
        kind: 'thinking',
        status: msg.streaming ? 'running' : 'success',
        streaming: Boolean(msg.streaming),
        timestamp: msg.timestamp,
        title,
      };
      group.steps.push(step);
      group.timeline.push({ kind: 'step', step });
      continue;
    }

    // Diff step + aggregated turn file edit summary
    if (msg.kind === 'diff') {
      const { title, subtitle } = formatStepSummary(msg, language);
      const stepId = msg.streamID || msg.messageKey || `diff-${i}`;
      const step: WorkflowStep = {
        filePath: msg.filePath,
        id: stepId,
        kind: 'diff',
        newText: msg.newText || '',
        oldText: msg.oldText || '',
        status: msg.streaming ? 'running' : 'success',
        streaming: Boolean(msg.streaming),
        subtitle,
        timestamp: msg.timestamp,
        title,
        toolName: msg.toolName,
        toolUseId: msg.toolUseId,
      };
      group.steps.push(step);
      group.timeline.push({ kind: 'step', step });
      if (msg.toolUseId) steps.set(msg.toolUseId, step);
      if (msg.filePath) {
        let diff = diffCounts.get(msg);
        if (!diff) {
          diff = quickLineDiffCounts(msg.oldText, msg.newText);
          diffCounts.set(msg, diff);
        }
        const existing = editedFiles.get(msg.filePath);
        if (existing) {
          existing.added += diff.added;
          existing.removed += diff.removed;
          existing.newText = msg.newText || existing.newText;
        } else {
          editedFiles.set(msg.filePath, {
            added: diff.added,
            filePath: msg.filePath,
            newText: msg.newText || '',
            oldText: msg.oldText || '',
            removed: diff.removed,
            status: msg.toolName === 'Write' && !(msg.oldText || '') ? 'added' : 'modified',
          });
        }
      }
      continue;
    }

    // Tool result pairing into existing step by toolUseId
    if (isToolResult(msg) && msg.toolUseId) {
      const targetStep = steps.get(msg.toolUseId);
      if (targetStep) {
        targetStep.resultText = msg.text || '';
        targetStep.isError = Boolean(msg.isError || msg.kind === 'error');
        targetStep.status = targetStep.isError ? 'error' : 'success';
        targetStep.streaming = false;
        if (targetStep.isError) targetStep.kind = 'error';
        continue;
      }
    }

    // Generic tool call or standalone tool error
    if (msg.role === 'tool' || msg.kind === 'tool' || msg.kind === 'error') {
      const { title, subtitle } = formatStepSummary(msg, language);
      const step: WorkflowStep = {
        filePath: msg.filePath || (typeof msg.toolInput?.file_path === 'string' ? msg.toolInput.file_path : undefined),
        id: msg.streamID || msg.messageKey || `tool-${i}`,
        inputText: msg.text || '',
        isError: Boolean(msg.isError || msg.kind === 'error'),
        kind: msg.kind === 'error' || msg.isError ? 'error' : 'tool',
        status: msg.isError || msg.kind === 'error' ? 'error' : msg.streaming ? 'running' : 'success',
        streaming: Boolean(msg.streaming),
        subtitle,
        timestamp: msg.timestamp,
        title,
        toolInput: msg.toolInput,
        toolName: msg.toolName,
        toolUseId: msg.toolUseId,
      };
      group.steps.push(step);
      group.timeline.push({ kind: 'step', step });
      if (msg.toolUseId) steps.set(msg.toolUseId, step);
      continue;
    }

    // Assistant prose reply
    if (msg.role === 'assistant' && typeof msg.text === 'string' && msg.text.length > 0) {
      const answer = {
        id: msg.streamID || msg.messageKey || `ans-${i}`,
        streaming: Boolean(msg.streaming),
        text: msg.text,
      };
      group.answerBlocks.push(answer);
      group.timeline.push({ kind: 'answer', answer });
    }
  }

  group.editedFiles = [...editedFiles.values()];
  return group;
}

interface TurnRecords {
  id: string;
  turnIndex: number;
  user?: PrettyTermMessage;
  records: PrettyTermMessage[];
  rendered?: RenderedAssistantTurn;
}

function userRow(message: PrettyTermMessage, turn: TurnRecords): RenderedUserTurn {
  return {
    id: turn.id + ':user',
    images: message.images ?? [],
    kind: 'user',
    text: message.text ?? '',
    timestamp: message.timestamp,
    turnIndex: turn.turnIndex,
  };
}

/** Index persisted rows once. Live records only project the tail and any tool
 * or question owner touched by that snapshot. */
export class TranscriptProjection {
  state = emptyTranscript();
  rowIds: readonly string[] = [];
  private groups: TurnRecords[] = [];
  private persistedIds: string[] = [];
  private persistedRows = new Map<string, RenderedTurn>();
  private liveRows = new Map<string, RenderedTurn>();
  private liveIds: string[] = [];
  private recordLocations = new Map<string, { turn: TurnRecords; index: number }>();
  private toolOwners = new Map<string, TurnRecords>();
  private questions = new Map<string, QuestionState>();
  private liveQuestions = new Map<string, QuestionState>();
  private streamMessages: PrettyTermMessage[] = [];
  private streamGeneration = '';
  private streamRevision = -1;
  private userCount = 0;
  private language: UILanguage;

  constructor(language: UILanguage) {
    this.language = language;
  }

  row(id: string): RenderedTurn | undefined {
    return this.liveRows.get(id) ?? this.persistedRows.get(id);
  }

  private updateMeta(meta: TranscriptMetadata) {
    const { awaitingReply, cwd, model, title } = meta;
    const prev = this.state;
    const next = {
      ...prev,
      awaitingReply: awaitingReply ?? prev.awaitingReply,
      cwd: cwd ?? prev.cwd,
      model: model ?? prev.model,
      title: title ?? prev.title,
    };
    if (next.awaitingReply !== prev.awaitingReply || next.cwd !== prev.cwd ||
        next.model !== prev.model || next.title !== prev.title) this.state = next;
  }

  private updateQuestions(updates: TranscriptMetadata['questionUpdates'], dirty: Set<TurnRecords>) {
    for (const update of updates ?? []) {
      if (!update.toolUseId) continue;
      const state = { answerText: update.answerText ?? '', answered: Boolean(update.answered) };
      const previous = this.questions.get(update.toolUseId);
      if (previous?.answerText === state.answerText && previous.answered === state.answered) continue;
      this.questions.set(update.toolUseId, state);
      const owner = this.toolOwners.get(update.toolUseId);
      if (owner) dirty.add(owner);
    }
  }

  private projectPersisted(turn: TurnRecords) {
    if (!turn.records.length) return;
    turn.rendered = projectAssistant(turn.id, turn.turnIndex, turn.records,
      this.state.model, this.questions, this.language, false);
    this.persistedRows.set(turn.id, turn.rendered);
  }

  replace(meta: TranscriptMetadata) {
    const sameSession = this.state.sessionId === meta.sessionId;
    if (!sameSession) {
      this.state = { ...emptyTranscript(), sessionId: meta.sessionId };
      this.streamMessages = [];
      this.liveQuestions.clear();
      this.streamGeneration = '';
      this.streamRevision = -1;
    }
    this.groups = [];
    this.persistedIds = [];
    this.persistedRows.clear();
    this.liveRows.clear();
    this.liveIds = [];
    this.recordLocations.clear();
    this.toolOwners.clear();
    this.questions.clear();
    this.rowIds = [];
    this.userCount = 0;
    this.append(meta, meta.messages ?? []);
  }

  append(meta: TranscriptMetadata, records: PrettyTermMessage[]) {
    if (meta.sessionId !== this.state.sessionId) return;
    this.updateMeta(meta);
    const dirty = new Set<TurnRecords>();
    for (const message of records) {
      let turn = this.groups.at(-1);
      if (message.role === 'user') {
        const turnIndex = this.userCount++;
        turn = { id: `turn:${message.messageKey || turnIndex}`, records: [], turnIndex, user: message };
        this.groups.push(turn);
        const row = userRow(message, turn);
        this.persistedRows.set(row.id, row);
        this.persistedIds.push(row.id);
        if (message.messageKey) this.recordLocations.set(message.messageKey, { turn, index: -1 });
        continue;
      }
      if (!turn) {
        turn = { id: 'turn:leading', records: [], turnIndex: 0 };
        this.groups.push(turn);
      }
      if (message.toolUseId && isToolResult(message)) {
        turn = this.toolOwners.get(message.toolUseId) ?? turn;
      } else if (message.toolUseId) {
        this.toolOwners.set(message.toolUseId, turn);
      }
      if (message.messageKey) {
        this.recordLocations.set(message.messageKey, { turn, index: turn.records.length });
      }
      if (!turn.records.length) this.persistedIds.push(turn.id);
      turn.records.push(message);
      dirty.add(turn);
    }
    this.updateQuestions(meta.questionUpdates, dirty);
    for (const turn of dirty) this.projectPersisted(turn);
    this.projectLive();
  }

  patch(meta: TranscriptMetadata, records: PrettyTermMessage[]) {
    if (meta.sessionId !== this.state.sessionId) return;
    this.updateMeta(meta);
    const dirty = new Set<TurnRecords>();
    for (const message of records) {
      const location = message.messageKey && this.recordLocations.get(message.messageKey);
      if (!location) continue;
      const { turn, index } = location;
      if (index < 0) {
        turn.user = message;
        const row = userRow(message, turn);
        this.persistedRows.set(row.id, row);
      } else {
        turn.records[index] = message;
        dirty.add(turn);
      }
    }
    this.updateQuestions(meta.questionUpdates, dirty);
    for (const turn of dirty) this.projectPersisted(turn);
    this.projectLive();
  }

  setLanguage(language: UILanguage) {
    if (language === this.language) return;
    this.language = language;
    for (const turn of this.groups) this.projectPersisted(turn);
    this.projectLive();
  }

  setWaiting(waiting: boolean) {
    if (this.state.awaitingReply === waiting) return;
    this.state = { ...this.state, awaitingReply: waiting };
    this.projectLive();
  }

  stream(snapshot: StreamPayload) {
    if (snapshot.sessionId !== this.state.sessionId) return;
    const generation = snapshot.generation ?? '';
    if (generation === this.streamGeneration && snapshot.revision !== undefined &&
        snapshot.revision <= this.streamRevision) return;
    this.streamGeneration = generation;
    this.streamRevision = snapshot.revision ?? -1;
    this.streamMessages = snapshot.messages ?? [];
    this.liveQuestions.clear();
    for (const update of snapshot.questionUpdates ?? []) {
      if (update.toolUseId) this.liveQuestions.set(update.toolUseId, {
        answerText: update.answerText ?? '',
        answered: Boolean(update.answered),
      });
    }
    const compacting = Boolean(snapshot.compacting);
    if (this.state.streamActive !== snapshot.active || this.state.compacting !== compacting) {
      this.state = { ...this.state, streamActive: snapshot.active, compacting };
    }
    this.projectLive();
  }

  private projectLive() {
    this.liveRows.clear();
    const previousLiveIds = this.liveIds;
    this.liveIds = [];
    const liveRecords = new Map<TurnRecords, PrettyTermMessage[]>();
    const active = this.state.awaitingReply || this.state.streamActive;
    let tail = this.groups.at(-1);
    let nextUser = this.userCount;

    for (const message of this.streamMessages) {
      if (message.messageKey && this.recordLocations.has(message.messageKey)) continue;
      if (message.role === 'user') {
        const turnIndex = nextUser++;
        tail = { id: `turn:${message.messageKey || turnIndex}`, turnIndex, records: [] };
        const row = userRow(message, tail);
        this.liveRows.set(row.id, row);
        this.liveIds.push(row.id);
        continue;
      }
      tail ??= { id: 'turn:leading', turnIndex: 0, records: [] };
      const owner = message.toolUseId && isToolResult(message) ? this.toolOwners.get(message.toolUseId) : undefined;
      const turn = owner ?? tail;
      const extra = liveRecords.get(turn);
      if (extra) extra.push(message);
      else liveRecords.set(turn, [message]);
    }
    if (active) {
      tail ??= { id: 'turn:leading', turnIndex: 0, records: [] };
      if (!liveRecords.has(tail)) liveRecords.set(tail, []);
    }
    for (const [id, state] of this.liveQuestions) {
      const persisted = this.questions.get(id);
      const owner = this.toolOwners.get(id);
      if (owner && (persisted?.answered !== state.answered || persisted?.answerText !== state.answerText) &&
          !liveRecords.has(owner)) liveRecords.set(owner, []);
    }
    for (const [turn, extra] of liveRecords) {
      const questions = new Map<string, QuestionState>();
      const records = [...turn.records, ...extra];
      for (const record of records) {
        if (record.kind !== 'question' || !record.toolUseId) continue;
        const id = record.toolUseId;
        const persisted = this.questions.get(id);
        const answer = persisted?.answered ? persisted : this.liveQuestions.get(id) ?? persisted;
        if (answer) questions.set(id, answer);
      }
      const projected = projectAssistant(turn.id, turn.turnIndex, records, this.state.model,
        questions, this.language, active && turn === tail);
      this.liveRows.set(turn.id, projected);
      if (!this.persistedRows.has(turn.id)) this.liveIds.push(turn.id);
    }
    if (this.rowIds.length !== this.persistedIds.length + this.liveIds.length ||
        previousLiveIds.length !== this.liveIds.length ||
        previousLiveIds.some((id, index) => id !== this.liveIds[index])) {
      this.rowIds = [...this.persistedIds, ...this.liveIds];
    }
  }
}
