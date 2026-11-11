import { CodeDiff, Highlighter, Markdown } from './RichContent';
import { useTurnState } from '@/bridge/store';
import Claude from '@lobehub/icons/es/Claude';
import { ActionIcon, Button, Input, Tag } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  AlertCircle,
  Brain,
  Check,
  ChevronDown,
  ChevronRight,
  Copy,
  FileCode2,
  FileEdit,
  Loader2,
  Quote,
  Terminal,
  X,
} from 'lucide-react';
import { AnimatePresence } from 'motion/react';
import * as m from 'motion/react-m';
import { createPortal } from 'react-dom';
import { memo, useCallback, useEffect, useMemo, useState } from 'react';

import type { UILanguage } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import type {
  QuestionBlock,
  RenderedAssistantTurn,
  RenderedUserTurn,
  TurnEditedFile,
  WorkflowStep,
} from '@/bridge/transcript';
import { groupAssistantTimeline } from '@/bridge/transcript';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  userRow: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-end',
    marginBlock: 8,
    width: '100%',
  },
  userBubble: {
    backgroundColor: cssVar.colorFillTertiary,
    borderRadius: 14,
    boxSizing: 'border-box',
    color: cssVar.colorText,
    fontSize: 14,
    lineHeight: 1.6,
    maxWidth: '82%',
    paddingBlock: 10,
    paddingInline: 14,
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  },
  userImages: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 8,
    justifyContent: 'flex-end',
    marginBottom: 8,
    maxWidth: '82%',
  },
  userThumb: {
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 10,
    borderStyle: 'solid',
    borderWidth: 1,
    maxHeight: 160,
    maxWidth: 220,
    objectFit: 'cover',
  },
  userThumbButton: {
    backgroundColor: 'transparent',
    borderWidth: 0,
    borderRadius: 10,
    cursor: 'zoom-in',
    display: 'block',
    lineHeight: 0,
    overflow: 'hidden',
    padding: 0,
  },
  imageLightbox: {
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.84)',
    display: 'flex',
    inset: 0,
    justifyContent: 'center',
    position: 'fixed',
    zIndex: 10000,
  },
  imageLightboxImage: {
    display: 'block',
    height: '80vh',
    objectFit: 'contain',
    width: '80vw',
  },
  imageLightboxClose: {
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.16)',
    borderRadius: 999,
    borderWidth: 0,
    color: 'white',
    cursor: 'pointer',
    display: 'flex',
    height: 40,
    justifyContent: 'center',
    position: 'fixed',
    right: 20,
    top: 20,
    width: 40,
  },
  collapseMoreBtn: {
    backgroundColor: 'transparent',
    borderWidth: 0,
    color: cssVar.colorPrimary,
    cursor: 'pointer',
    fontSize: 12,
    fontWeight: 500,
    marginTop: 4,
    padding: 0,
  },
  assistantGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    marginBlock: 12,
    width: '100%',
  },
  assistantHeader: {
    alignItems: 'center',
    display: 'flex',
    gap: 8,
  },
  modelName: {
    color: cssVar.colorText,
    fontSize: 13,
    fontWeight: 600,
  },
  timeLabel: {
    color: cssVar.colorTextTertiary,
    fontSize: 12,
  },
  workflowSummary: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderWidth: 0,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'inline-flex',
    fontSize: 13,
    gap: 6,
    paddingBlock: 3,
    paddingInline: 0,
    textAlign: 'left',
    ':hover': {
      color: cssVar.colorText,
    },
  },
  stepList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
    paddingLeft: 2,
  },
  stepRow: {
    alignItems: 'center',
    borderRadius: 8,
    cursor: 'pointer',
    display: 'flex',
    gap: 8,
    paddingBlock: 4,
    paddingInline: 6,
    transition: 'background-color 0.12s ease',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  stepRowExpanded: {
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorPrimaryBorder,
    borderStyle: 'solid',
    borderWidth: 1,
  },
  stepIcon: {
    alignItems: 'center',
    borderRadius: 99,
    display: 'flex',
    flexShrink: 0,
    height: 18,
    justifyContent: 'center',
    width: 18,
  },
  stepTitle: {
    color: cssVar.colorTextSecondary,
    flex: 1,
    fontSize: 13,
    minWidth: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  stepDetail: {
    borderLeftColor: cssVar.colorBorderSecondary,
    borderLeftStyle: 'solid',
    borderLeftWidth: 2,
    marginBottom: 6,
    marginLeft: 14,
    paddingLeft: 12,
  },
  stepPathHint: {
    color: cssVar.colorTextTertiary,
    fontFamily: cssVar.fontFamilyCode,
    fontSize: 11.5,
    marginBottom: 6,
    wordBreak: 'break-all',
  },
  preBox: {
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 8,
    borderStyle: 'solid',
    borderWidth: 1,
    color: cssVar.colorTextSecondary,
    fontFamily: cssVar.fontFamilyCode,
    fontSize: 12,
    lineHeight: 1.5,
    margin: 0,
    maxHeight: 280,
    overflow: 'auto',
    padding: 10,
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  },
  editedCard: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    marginTop: 4,
    overflow: 'hidden',
  },
  editedHeader: {
    alignItems: 'center',
    display: 'flex',
    gap: 10,
    justifyContent: 'space-between',
    paddingBlock: 10,
    paddingInline: 12,
  },
  editedTitleRow: {
    alignItems: 'center',
    display: 'flex',
    gap: 8,
    fontSize: 13,
    fontWeight: 500,
  },
  editedRow: {
    alignItems: 'center',
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 12.5,
    gap: 8,
    paddingBlock: 7,
    paddingInline: 12,
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  editedFooterBtn: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    borderWidth: 0,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 12,
    gap: 4,
    paddingBlock: 7,
    paddingInline: 12,
    width: '100%',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
      color: cssVar.colorText,
    },
  },
  questionCard: {
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    padding: 14,
  },
  footerBar: {
    alignItems: 'center',
    display: 'flex',
    gap: 8,
    justifyContent: 'space-between',
    marginTop: 2,
  },
  footerMeta: {
    color: cssVar.colorTextQuaternary,
    fontSize: 11.5,
  },
});

function formatShortTime(ts?: string): string {
  if (!ts) return '';
  const dt = new Date(ts);
  if (Number.isNaN(dt.getTime())) return '';
  return `${dt.getMonth() + 1}月${dt.getDate()}日 ${String(dt.getHours()).padStart(2, '0')}:${String(dt.getMinutes()).padStart(2, '0')}`;
}

function guessLang(path?: string): string {
  const ext = (path || '').split('.').pop()?.toLowerCase() || '';
  const map: Record<string, string> = {
    cjs: 'javascript',
    css: 'css',
    h: 'objective-c',
    html: 'html',
    js: 'javascript',
    json: 'json',
    jsx: 'jsx',
    m: 'objective-c',
    md: 'markdown',
    mjs: 'javascript',
    py: 'python',
    sh: 'bash',
    swift: 'swift',
    ts: 'typescript',
    tsx: 'tsx',
    yaml: 'yaml',
    yml: 'yaml',
    zsh: 'bash',
  };
  return map[ext] || 'text';
}

const StepItemView = memo<{
  language: UILanguage;
  onOpenFile: (path: string) => void;
  step: WorkflowStep;
  sessionId: string;
  turnId: string;
}>(({ language, onOpenFile, sessionId, step, turnId }) => {
  const [expanded, setExpanded] = useTurnState(sessionId, `${turnId}:step:${step.id}`, false);

  const iconNode = useMemo(() => {
    if (step.status === 'running') {
      return <Loader2 className="pt-spin" color="#1677ff" size={14} />;
    }
    if (step.status === 'error') {
      return <AlertCircle color="#ff4d4f" size={14} />;
    }
    if (step.kind === 'thinking') {
      return <Brain color="#722ed1" size={14} />;
    }
    if (step.toolName === 'Bash' || step.toolName === 'run_command') {
      return <Terminal color="#52c41a" size={14} />;
    }
    return <Check color="#52c41a" size={14} />;
  }, [step.kind, step.status, step.toolName]);

  return (
    <div>
      <div
        data-pt-workflow-step="1"
        onClick={() => setExpanded((v) => !v)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            setExpanded((v) => !v);
          }
        }}
        {...sx(styles.stepRow, expanded && styles.stepRowExpanded)}
      >
        <span {...sx(styles.stepIcon)}>{iconNode}</span>
        <span {...sx(styles.stepTitle)}>{step.title}</span>
        {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
      </div>

      <AnimatePresence initial={false}>
        {expanded && (
          <m.div
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            initial={{ height: 0, opacity: 0 }}
            style={{ overflow: 'hidden' }}
            transition={{ duration: 0.16, ease: 'easeOut' }}
          >
            <div {...sx(styles.stepDetail)}>
              {step.filePath && (
                <div
                  onClick={() => onOpenFile(step.filePath!)}
                  {...sx(styles.stepPathHint, { cursor: 'pointer' })}
                >
                  {step.filePath}
                </div>
              )}

              {step.kind === 'diff' ? (
                <CodeDiff
                  defaultExpand
                  fileName={step.filePath?.split('/').pop() || 'diff'}
                  fullFeatured={false}
                  language={guessLang(step.filePath)}
                  newContent={step.newText || ''}
                  oldContent={step.oldText || ''}
                  showHeader={false}
                  variant="borderless"
                  viewMode="unified"
                />
              ) : step.kind === 'thinking' ? (
                <pre {...sx(styles.preBox)}>{step.inputText}</pre>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {step.toolInput && typeof step.toolInput.command === 'string' && (
                    <Highlighter language="bash" showLanguage={false} variant="outlined">
                      {step.toolInput.command}
                    </Highlighter>
                  )}
                  {(step.resultText || step.inputText) && (
                    <pre {...sx(styles.preBox)}>
                      {step.resultText || step.inputText || (language === 'en' ? '(empty)' : '(无输出)')}
                    </pre>
                  )}
                </div>
              )}
            </div>
          </m.div>
        )}
      </AnimatePresence>
    </div>
  );
});

StepItemView.displayName = 'StepItemView';

const WorkflowStepGroup = memo<{
  groupId: string;
  language: UILanguage;
  onOpenFile: (path: string) => void;
  sessionId: string;
  steps: WorkflowStep[];
  turnId: string;
}>(({ groupId, language, onOpenFile, sessionId, steps, turnId }) => {
  const [expanded, setExpanded] = useTurnState(
    sessionId,
    `${turnId}:workflow:${groupId}`,
    false,
  );
  const isRunning = steps.some((step) => step.status === 'running');

  return (
    <div>
      <button
        aria-expanded={expanded}
        data-pt-workflow-summary="1"
        data-pt-workflow-group={groupId}
        onClick={() => setExpanded((value) => !value)}
        type="button"
        {...sx(styles.workflowSummary)}
      >
        <span>
          {isRunning
            ? language === 'en'
              ? `Running ${steps.length} steps…`
              : `正在执行 · 已运行 ${steps.length} 步…`
            : language === 'en'
              ? `Ran ${steps.length} steps`
              : `共运行 ${steps.length} 步`}
        </span>
        {expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
      </button>

      <AnimatePresence initial={false}>
        {expanded && (
          <m.div
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            initial={{ height: 0, opacity: 0 }}
            style={{ overflow: 'hidden' }}
            transition={{ duration: 0.18, ease: 'easeOut' }}
          >
            <div {...sx(styles.stepList)}>
              {steps.map((step) => (
                <StepItemView
                  key={step.id}
                  language={language}
                  onOpenFile={onOpenFile}
                  sessionId={sessionId}
                  step={step}
                  turnId={turnId}
                />
              ))}
            </div>
          </m.div>
        )}
      </AnimatePresence>
    </div>
  );
});

WorkflowStepGroup.displayName = 'WorkflowStepGroup';

const QuestionCardView = memo<{
  block: QuestionBlock;
  language: UILanguage;
  sessionId: string;
}>(({ block, language, sessionId }) => {
  const [selectedByQ, setSelectedByQ] = useTurnState<Record<string, string[]>>(sessionId, `question:${block.id}:choices`, {});
  const [customNote, setCustomNote] = useTurnState(sessionId, `question:${block.id}:note`, '');
  const [submitting, setSubmitting] = useState(false);

  const handleToggleOption = (question: string, label: string, multi?: boolean) => {
    setSelectedByQ((prev) => {
      const current = prev[question] ?? [];
      if (!multi) return { ...prev, [question]: [label] };
      const exists = current.includes(label);
      return {
        ...prev,
        [question]: exists ? current.filter((x) => x !== label) : [...current, label],
      };
    });
  };

  const handleSubmit = async () => {
    const answers: Record<string, string> = {};
    for (const q of block.questions) {
      const picked = selectedByQ[q.question] ?? [];
      const joined = [...picked, customNote.trim()].filter(Boolean).join(', ');
      if (joined) answers[q.question] = joined;
    }
    const answerText = Object.entries(answers)
      .map(([k, v]) => `${k}: ${v}`)
      .join('\n');
    if (!answerText) return;
    setSubmitting(true);
    await invokeNativeUI('answerQuestion', {
      answers,
      sessionId,
      text: answerText,
      toolUseId: block.toolUseId,
    });
    setSubmitting(false);
  };

  if (block.answered) {
    return (
      <div {...sx(styles.questionCard)}>
        <Tag color="success">{language === 'en' ? 'Answered' : '已作答'}</Tag>
        <div style={{ fontSize: 13, whiteSpace: 'pre-wrap' }}>{block.answerText}</div>
      </div>
    );
  }

  return (
    <div {...sx(styles.questionCard)}>
      {block.questions.map((q) => (
        <div key={q.question} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ fontSize: 13.5, fontWeight: 600 }}>{q.question}</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {(q.options ?? []).map((opt) => {
              const selected = (selectedByQ[q.question] ?? []).includes(opt.label);
              return (
                <Button
                  key={opt.label}
                  onClick={() => handleToggleOption(q.question, opt.label, q.multiSelect)}
                  size="small"
                  type={selected ? 'primary' : 'default'}
                >
                  {opt.label}
                </Button>
              );
            })}
          </div>
        </div>
      ))}
      <div style={{ display: 'flex', gap: 8 }}>
        <Input
          onChange={(e) => setCustomNote(e.target.value)}
          placeholder={language === 'en' ? 'Optional note...' : '补充说明（可选）...'}
          size="small"
          value={customNote}
        />
        <Button loading={submitting} onClick={() => void handleSubmit()} size="small" type="primary">
          {language === 'en' ? 'Submit Answer' : '提交回答'}
        </Button>
      </div>
    </div>
  );
});

QuestionCardView.displayName = 'QuestionCardView';

const EditedFilesCard = memo<{
  files: TurnEditedFile[];
  language: UILanguage;
  onReviewTurn: (turnIndex: number) => void;
  turnIndex: number;
  sessionId: string;
}>(({ files, language, onReviewTurn, sessionId, turnIndex }) => {
  const [expanded, setExpanded] = useTurnState(sessionId, `edits:${turnIndex}`, true);
  const totals = useMemo(() => {
    let added = 0;
    let removed = 0;
    for (const f of files) {
      added += f.added;
      removed += f.removed;
    }
    return { added, removed };
  }, [files]);

  if (files.length === 0) return null;

  return (
    <div {...sx(styles.editedCard)}>
      <div {...sx(styles.editedHeader)}>
        <div {...sx(styles.editedTitleRow)}>
          <FileEdit size={15} />
          <span>
            {language === 'en' ? `Edited ${files.length} files` : `已编辑 ${files.length} 个文件`}
          </span>
          <span style={{ color: '#22c55e', fontSize: 12, fontWeight: 600 }}>+{totals.added}</span>
          <span style={{ color: '#ef4444', fontSize: 12, fontWeight: 600 }}>-{totals.removed}</span>
        </div>
        <Button onClick={() => onReviewTurn(turnIndex)} size="small" type="text">
          {language === 'en' ? 'Review' : '审查改动'}
        </Button>
      </div>

      {expanded &&
        files.map((f) => (
          <div
            key={f.filePath}
            onClick={() => onReviewTurn(turnIndex)}
            role="button"
            tabIndex={0}
            {...sx(styles.editedRow)}
          >
            <span
              style={{
                backgroundColor: f.status === 'added' ? '#22c55e' : '#1677ff',
                borderRadius: 99,
                height: 6,
                width: 6,
              }}
            />
            <FileCode2 size={14} />
            <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {f.filePath}
            </span>
            <span style={{ color: '#22c55e', fontSize: 12 }}>+{f.added}</span>
            <span style={{ color: '#ef4444', fontSize: 12 }}>-{f.removed}</span>
            <ChevronRight size={13} />
          </div>
        ))}

      <button onClick={() => setExpanded((v) => !v)} type="button" {...sx(styles.editedFooterBtn)}>
        <span>
          {expanded
            ? language === 'en'
              ? 'Collapse files'
              : '收起文件'
            : language === 'en'
              ? `Show ${files.length} files`
              : `展开 ${files.length} 个文件`}
        </span>
      </button>
    </div>
  );
});

EditedFilesCard.displayName = 'EditedFilesCard';

export const UserTurnView = memo<{ language: UILanguage; sessionId: string; turn: RenderedUserTurn }>(
  ({ language, sessionId, turn }) => {
    const lines = turn.text.split('\n');
    const longInput = lines.length > 20;
    const [expanded, setExpanded] = useTurnState(sessionId, `${turn.id}:expand`, false);
    const visibleText = longInput && !expanded ? lines.slice(0, 14).join('\n') : turn.text;
    const [previewImage, setPreviewImage] = useState<{ alt: string; src: string } | null>(null);

    useEffect(() => {
      if (!previewImage) return;
      const closeOnEscape = (event: KeyboardEvent) => {
        if (event.key === 'Escape') setPreviewImage(null);
      };
      window.addEventListener('keydown', closeOnEscape);
      return () => window.removeEventListener('keydown', closeOnEscape);
    }, [previewImage]);

    return (
      <>
        <div data-pt-turn-index={turn.turnIndex} data-pt-turn-kind="user" {...sx(styles.userRow)}>
          {turn.images.length > 0 && (
            <div {...sx(styles.userImages)}>
              {turn.images.map((img, i) => {
                const dataUrl = img.dataUrl;
                if (!dataUrl) return null;
                const alt = img.name || 'image';
                return (
                  <button
                    aria-label={language === 'en' ? 'Enlarge image' : '放大图片'}
                    key={`${turn.id}-img-${i}`}
                    onClick={() => setPreviewImage({ alt, src: dataUrl })}
                    type="button"
                    {...sx(styles.userThumbButton)}
                  >
                    <img alt={alt} src={dataUrl} {...sx(styles.userThumb)} />
                  </button>
                );
              })}
            </div>
          )}
          {turn.text.length > 0 && (
            <div {...sx(styles.userBubble)}>
              <div>{visibleText}</div>
              {longInput && (
                <button
                  onClick={() => setExpanded((v) => !v)}
                  type="button"
                  {...sx(styles.collapseMoreBtn)}
                >
                  {expanded
                    ? language === 'en'
                      ? 'Collapse'
                      : '收起长输入'
                    : language === 'en'
                      ? `Show all (${lines.length} lines)`
                      : `展开全部 (${lines.length} 行)`}
                </button>
              )}
            </div>
          )}
        </div>
        {previewImage && createPortal(
          <div onClick={() => setPreviewImage(null)} {...sx(styles.imageLightbox)}>
            <div
              aria-label={language === 'en' ? 'Image preview' : '图片预览'}
              aria-modal="true"
              onClick={(event) => event.stopPropagation()}
              role="dialog"
            >
              <img alt={previewImage.alt} src={previewImage.src} {...sx(styles.imageLightboxImage)} />
            </div>
            <button
              aria-label={language === 'en' ? 'Close image preview' : '关闭图片预览'}
              onClick={() => setPreviewImage(null)}
              type="button"
              {...sx(styles.imageLightboxClose)}
            >
              <X size={20} />
            </button>
          </div>,
          document.body,
        )}
      </>
    );
  },
);

UserTurnView.displayName = 'UserTurnView';

export const AssistantTurnView = memo<{
  language: UILanguage;
  onOpenFile: (path: string) => void;
  onQuote: (text: string) => void;
  onReviewTurn: (turnIndex: number) => void;
  sessionId: string;
  turn: RenderedAssistantTurn;
}>(({ language, onOpenFile, onQuote, onReviewTurn, sessionId, turn }) => {
  const [copied, setCopied] = useState(false);

  const combinedAnswerText = useMemo(
    () => turn.answerBlocks.map((b) => b.text).join('\n\n'),
    [turn.answerBlocks],
  );
  const groupedTimeline = groupAssistantTimeline(turn.timeline);

  const handleCopyTurn = useCallback(() => {
    if (!combinedAnswerText) return;
    void invokeNativeUI('copyText', {
      label: language === 'en' ? 'Copied reply' : '已复制回复内容',
      text: combinedAnswerText,
    });
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, [combinedAnswerText, language]);

  return (
    <div data-pt-turn-index={turn.turnIndex} data-pt-turn-kind="assistant" {...sx(styles.assistantGroup)}>
      <div {...sx(styles.assistantHeader)}>
        <Claude.Color size={18} />
        <span {...sx(styles.modelName)}>{turn.model || 'Claude'}</span>
        {turn.timestamp && <span {...sx(styles.timeLabel)}>{formatShortTime(turn.timestamp)}</span>}
        {turn.hasStreaming && (
          <Tag color="blue">{language === 'en' ? 'Streaming...' : '实时生成中'}</Tag>
        )}
      </div>

      {turn.waitingPlaceholder && turn.steps.length === 0 && turn.answerBlocks.length === 0 && (
        <div style={{ alignItems: 'center', color: 'var(--lobe-color-text-secondary)', display: 'flex', fontSize: 13, gap: 8 }}>
          <Loader2 className="pt-spin" size={14} />
          <span>{language === 'en' ? 'Claude is thinking...' : 'Claude 正在思考并响应…'}</span>
        </div>
      )}

      {groupedTimeline.map((item) => {
        if (item.kind === 'answer') {
          return (
            <div key={`answer:${item.answer.id}`} data-pt-assistant-prose="1">
              <Markdown
                animated={item.answer.streaming}
                enableLatex
                enableMermaid
                enableStream
                variant="chat"
              >
                {item.answer.text}
              </Markdown>
            </div>
          );
        }
        if (item.kind === 'question') {
          return <QuestionCardView key={`question:${item.question.id}`} block={item.question} language={language} sessionId={sessionId} />;
        }

        return (
          <WorkflowStepGroup
            groupId={item.id}
            key={`step-group:${item.id}`}
            language={language}
            onOpenFile={onOpenFile}
            sessionId={sessionId}
            steps={item.steps}
            turnId={turn.id}
          />
        );
      })}

      <EditedFilesCard
        files={turn.editedFiles}
        language={language}
        onReviewTurn={onReviewTurn}
        sessionId={sessionId}
        turnIndex={turn.turnIndex}
      />

      {combinedAnswerText.length > 0 && !turn.hasStreaming && (
        <div {...sx(styles.footerBar)}>
          <div style={{ alignItems: 'center', display: 'flex', gap: 2 }}>
            <ActionIcon
              icon={copied ? Check : Copy}
              onClick={handleCopyTurn}
              size="small"
              title={language === 'en' ? 'Copy reply' : '复制全文'}
            />
            <ActionIcon
              icon={Quote}
              onClick={() => onQuote(combinedAnswerText)}
              size="small"
              title={language === 'en' ? 'Quote into composer' : '引用到输入框'}
            />
          </div>
          <div {...sx(styles.footerMeta)}>
            {turn.model}
            {turn.usage?.outputTokens ? ` · ${turn.usage.outputTokens} tok` : ''}
            {turn.usage?.costUSD ? ` · $${turn.usage.costUSD.toFixed(3)}` : ''}
          </div>
        </div>
      )}
    </div>
  );
});

AssistantTurnView.displayName = 'AssistantTurnView';
