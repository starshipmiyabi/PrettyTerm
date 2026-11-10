import Claude from '@lobehub/icons/es/Claude';
import { ActionIcon, DropdownMenu, Input, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  ArrowUp,
  Check,
  ChevronDown,
  FileText,
  FolderOpen,
  Loader2,
  Plus,
  Search,
  Slash,
  Square,
  X,
} from 'lucide-react';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { ModelOption, Surface } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { clearSubmittedQuote, composerEditorId, usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

import { ControlBar } from './ControlBar';

const DEFAULT_MODELS: ModelOption[] = [
  { id: 'claude-fable-5', label: 'Claude Fable 5', shortLabel: 'claude-fable-5' },
  { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', shortLabel: 'claude-opus-5-5' },
  { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', shortLabel: 'claude-sonnet-5-5' },
  { id: 'claude-sonnet-4-6', label: 'Claude Sonnet 4.6', shortLabel: 'claude-sonnet-4-6' },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', shortLabel: 'claude-haiku-4-5' },
];

const DEFAULT_EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

const styles = stylex.create({
  wrapper: {
    boxSizing: 'border-box',
    flexShrink: 0,
    marginInline: 'auto',
    maxWidth: 848,
    paddingBottom: 10,
    paddingInline: 24,
    position: 'relative',
    width: '100%',
  },
  card: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 16,
    borderStyle: 'solid',
    borderWidth: 1,
    boxShadow: cssVar.boxShadowTertiary,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    paddingBlock: 10,
    paddingInline: 14,
    position: 'relative',
    transition: 'border-color 0.15s ease',
  },
  attachStrip: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
  },
  imgChip: {
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 8,
    borderStyle: 'solid',
    borderWidth: 1,
    height: 44,
    overflow: 'hidden',
    position: 'relative',
    width: 44,
  },
  imgChipClose: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.65)',
    borderRadius: 99,
    borderWidth: 0,
    color: '#fff',
    cursor: 'pointer',
    display: 'flex',
    height: 16,
    justifyContent: 'center',
    padding: 0,
    position: 'absolute',
    right: 2,
    top: 2,
    width: 16,
  },
  fileChip: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillTertiary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 8,
    borderStyle: 'solid',
    borderWidth: 1,
    color: cssVar.colorText,
    display: 'inline-flex',
    fontSize: 12,
    gap: 5,
    paddingBlock: 4,
    paddingInline: 8,
  },
  quoteBanner: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillQuaternary,
    borderLeftColor: cssVar.colorPrimary,
    borderLeftStyle: 'solid',
    borderLeftWidth: 2,
    borderRadius: 6,
    color: cssVar.colorTextSecondary,
    display: 'flex',
    fontSize: 12,
    gap: 8,
    justifyContent: 'space-between',
    paddingBlock: 5,
    paddingInline: 8,
  },
  textarea: {
    backgroundColor: 'transparent',
    borderWidth: 0,
    color: cssVar.colorText,
    fontFamily: 'inherit',
    fontSize: 14,
    lineHeight: 1.55,
    maxHeight: 180,
    minHeight: 44,
    outline: 'none',
    padding: 0,
    resize: 'none',
    width: '100%',
  },
  toolbar: {
    alignItems: 'center',
    display: 'flex',
    gap: 8,
    justifyContent: 'space-between',
  },
  toolbarLeft: {
    alignItems: 'center',
    display: 'flex',
    gap: 2,
  },
  toolbarRight: {
    alignItems: 'center',
    display: 'flex',
    gap: 6,
    position: 'relative',
  },
  modelBtn: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 8,
    borderWidth: 0,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'inline-flex',
    fontSize: 12.5,
    fontWeight: 500,
    gap: 5,
    height: 28,
    paddingInline: 8,
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
      color: cssVar.colorText,
    },
  },
  sendBtn: {
    alignItems: 'center',
    backgroundColor: cssVar.colorText,
    borderRadius: 8,
    borderWidth: 0,
    color: cssVar.colorBgContainer,
    cursor: 'pointer',
    display: 'inline-flex',
    height: 28,
    justifyContent: 'center',
    transition: 'opacity 0.15s ease',
    width: 28,
  },
  sendBtnDisabled: {
    backgroundColor: cssVar.colorFillSecondary,
    color: cssVar.colorTextQuaternary,
    cursor: 'not-allowed',
  },
  stopBtn: {
    alignItems: 'center',
    backgroundColor: cssVar.colorError,
    borderRadius: 8,
    borderWidth: 0,
    color: '#fff',
    cursor: 'pointer',
    display: 'inline-flex',
    height: 28,
    justifyContent: 'center',
    width: 28,
  },
  popoverCard: {
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 14,
    borderStyle: 'solid',
    borderWidth: 1,
    bottom: 44,
    boxShadow: cssVar.boxShadowSecondary,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    padding: 10,
    position: 'absolute',
    right: 0,
    width: 310,
    zIndex: 50,
  },
  modelItem: {
    alignItems: 'center',
    borderRadius: 8,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 13,
    gap: 8,
    justifyContent: 'space-between',
    paddingBlock: 7,
    paddingInline: 8,
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
    },
  },
  modelItemActive: {
    backgroundColor: cssVar.colorFillTertiary,
    fontWeight: 600,
  },
  effortPills: {
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    display: 'flex',
    gap: 4,
    paddingTop: 8,
  },
  effortChip: {
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: 'transparent',
    borderRadius: 6,
    borderStyle: 'solid',
    borderWidth: 1,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    flex: 1,
    fontSize: 11.5,
    paddingBlock: 4,
    textAlign: 'center',
    ':hover': {
      color: cssVar.colorText,
    },
  },
  effortChipActive: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorPrimary,
    color: cssVar.colorPrimary,
    fontWeight: 600,
  },
  slashMenu: {
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    bottom: '100%',
    boxShadow: cssVar.boxShadowSecondary,
    left: 0,
    marginBottom: 8,
    maxHeight: 280,
    overflowY: 'auto',
    padding: 6,
    position: 'absolute',
    width: 380,
    zIndex: 45,
  },
  slashRow: {
    alignItems: 'center',
    borderRadius: 8,
    cursor: 'pointer',
    display: 'flex',
    gap: 10,
    paddingBlock: 7,
    paddingInline: 10,
  },
  slashRowActive: {
    backgroundColor: cssVar.colorFillTertiary,
  },
});

export interface ChatInputProps {
  compact?: boolean;
  onOpenGitDir?: () => void;
  surface: Surface;
}

export const ChatInput = memo<ChatInputProps>(({ compact, onOpenGitDir, surface }) => {
  const activeSession = usePTSlice('activeSession');
  const activeTab = usePTSlice('activeTab');
  const composer = usePTSlice('composer');
  const commandResults = usePTSlice('commandResults');
  const composerQuote = usePTSlice('composerQuote');
  const language = usePTSlice('language');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const setComposerQuote = usePTSlice('setComposerQuote');
  const transcript = usePTSlice('transcript');
  const claudeSettings = usePTSlice('claudeSettings');

  const [draft, setDraft] = useState(composer.draft);
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashIndex, setSlashIndex] = useState(0);
  const [modelPopoverOpen, setModelPopoverOpen] = useState(false);
  const [modelFilter, setModelFilter] = useState('');
  const [modelChange, setModelChange] = useState<{ editorId: string; model: string }>();
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState('');

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const isComposingRef = useRef(false);
  const popoverRef = useRef<HTMLDivElement>(null);

  // Sync draft when switching workspace tabs
  const tabId = surface === 'floating' ? selectedSessionId : activeTab?.id || '';
  const editorId = composerEditorId(tabId, selectedSessionId);
  const composerMatches = composer.id === tabId && composer.sessionId === selectedSessionId;
  const tabDraft = composer.draft;
  const pendingDraft = useRef<{ editorId: string; changed: boolean } | null>(null);
  const prevTabRef = useRef('');
  const editorRef = useRef(editorId);
  const modelRequestRef = useRef(0);
  editorRef.current = editorId;
  useEffect(() => {
    if (composerMatches && prevTabRef.current !== editorId) {
      prevTabRef.current = editorId;
      setSubmitError('');
      setDraft(tabDraft);
    }
  }, [composerMatches, editorId, tabDraft]);

  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = 'auto';
    ta.style.height = `${Math.min(180, Math.max(44, ta.scrollHeight))}px`;
  }, [draft]);

  useEffect(() => {
    if (!modelPopoverOpen) return;
    const onDocDown = (e: MouseEvent) => {
      if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
        setModelPopoverOpen(false);
      }
    };
    document.addEventListener('mousedown', onDocDown);
    return () => document.removeEventListener('mousedown', onDocDown);
  }, [modelPopoverOpen]);

  const pendingImages = composerMatches ? composer.pendingImages : [];
  const pendingFiles = composerMatches ? composer.pendingFiles : [];
  const isAwaiting = Boolean(
    (transcript.sessionId === selectedSessionId && (transcript.awaitingReply || transcript.streamActive)) ||
    activeTab?.responding || activeSession?.responding,
  );
  const canSubmit =
    Boolean(selectedSessionId) && composerMatches &&
    !submitting &&
    (draft.trim().length > 0 || pendingImages.length > 0 || pendingFiles.length > 0);

  const handleDraftChange = useCallback(
    (next: string) => {
      if (pendingDraft.current?.editorId === editorId) pendingDraft.current.changed = true;
      setDraft(next);
      if (tabId) {
        void invokeNativeUI('updateDraft', { draft: next, sessionId: selectedSessionId, tabId });
      }
      if (next.startsWith('/') && !/\s/.test(next)) {
        setSlashOpen(true);
        setSlashIndex(0);
        void invokeNativeUI('querySlashCommands', {
          query: next.slice(1),
          sessionId: selectedSessionId,
        });
      } else {
        setSlashOpen(false);
      }
    },
    [editorId, selectedSessionId, tabId],
  );

  const handleChooseSlash = useCallback(
    (cmdName: string) => {
      const next = `/${cmdName} `;
      handleDraftChange(next);
      setSlashOpen(false);
      textareaRef.current?.focus();
    },
    [handleDraftChange],
  );

  const handleSubmit = useCallback(async () => {
    if (!selectedSessionId || !composerMatches || prevTabRef.current !== editorId || pendingDraft.current) return;
    const combinedText = [composerQuote.trim(), draft.trim()].filter(Boolean).join('\n\n');
    if (!combinedText && pendingImages.length === 0 && pendingFiles.length === 0) return;

    const submitted = { editorId, changed: false };
    pendingDraft.current = submitted;
    setSubmitError('');
    setSubmitting(true);
    setSlashOpen(false);
    const res = await invokeNativeUI<{ accepted: boolean; clearedDraft: boolean }>('submitMessage', {
      sessionId: selectedSessionId,
      surface,
      tabId,
      text: combinedText,
    });
    pendingDraft.current = null;
    setSubmitting(false);
    if (!res.ok && editorRef.current === editorId) {
      setSubmitError(res.error ?? '');
    }
    if (res.ok && res.data?.accepted) {
      clearSubmittedQuote(editorId, composerQuote);
      if (res.data.clearedDraft && editorRef.current === editorId && !submitted.changed) setDraft('');
    }
  }, [composerMatches, composerQuote, draft, editorId, pendingFiles.length, pendingImages.length, selectedSessionId, surface, tabId]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (isComposingRef.current || e.nativeEvent.isComposing || e.keyCode === 229) {
        return;
      }
      if (slashOpen && commandResults.items.length > 0) {
        if (e.key === 'ArrowDown') {
          e.preventDefault();
          setSlashIndex((i) => (i + 1) % commandResults.items.length);
          return;
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault();
          setSlashIndex((i) => (i - 1 + commandResults.items.length) % commandResults.items.length);
          return;
        }
        if (e.key === 'Tab' || (e.key === 'Enter' && !e.metaKey && !e.shiftKey)) {
          e.preventDefault();
          const chosen = commandResults.items[slashIndex];
          if (chosen) handleChooseSlash(chosen.name);
          return;
        }
        if (e.key === 'Escape') {
          e.preventDefault();
          setSlashOpen(false);
          return;
        }
      }
      if (e.key === 'Enter' && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
        e.preventDefault();
        if (!isAwaiting || draft.trim().startsWith('/')) {
          void handleSubmit();
        }
      }
    },
    [commandResults.items, draft, handleChooseSlash, handleSubmit, isAwaiting, slashIndex, slashOpen],
  );

  const handlePaste = useCallback(
    (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
      const items = e.clipboardData?.items;
      if (!items) return;
      for (const item of Array.from(items)) {
        if (item.type.startsWith('image/')) {
          e.preventDefault();
          void invokeNativeUI('pasteClipboardImage', { surface });
          return;
        }
      }
    },
    [surface],
  );

  const models = claudeSettings?.availableModels ?? DEFAULT_MODELS;
  const efforts = claudeSettings?.effortLevels ?? DEFAULT_EFFORTS;
  const currentModel = claudeSettings?.sessionId === selectedSessionId ? claudeSettings?.selectedModel : undefined;
  const currentEffort =
    activeSession?.effort || claudeSettings?.selectedEffort || 'high';

  const chooseModel = async (model: string) => {
    const revision = ++modelRequestRef.current;
    setModelChange({ editorId, model });
    setSubmitError('');
    const result = await invokeNativeUI('setModel', { model, sessionId: selectedSessionId });
    if (revision !== modelRequestRef.current) return;
    setModelChange(undefined);
    if (editorRef.current !== editorId) return;
    setModelPopoverOpen(false);
    if (!result.ok) setSubmitError(result.error ?? '');
  };

  const filteredModels = useMemo(() => {
    const q = modelFilter.trim().toLowerCase();
    if (!q) return models;
    return models.filter(
      (m) => m.id.toLowerCase().includes(q) || m.label.toLowerCase().includes(q),
    );
  }, [modelFilter, models]);

  const attachMenuItems = useMemo<DropdownItem[]>(
    () => [
      {
        icon: <FolderOpen size={14} />,
        key: 'pick-files',
        label: language === 'en' ? 'Add Files or Images...' : '选择本地文件 / 图片…',
        onClick: () => {
          void invokeNativeUI('pickAttachments', { surface });
        },
      },
    ],
    [language, surface],
  );

  return (
    <div {...sx(styles.wrapper, compact && { paddingInline: 12 })}>
      {slashOpen && commandResults.items.length > 0 && (
        <div data-pt-slash-menu="1" {...sx(styles.slashMenu)}>
          {commandResults.items.map((cmd, idx) => (
            <div
              key={cmd.name}
              onClick={() => handleChooseSlash(cmd.name)}
              onMouseEnter={() => setSlashIndex(idx)}
              role="button"
              tabIndex={0}
              {...sx(styles.slashRow, idx === slashIndex && styles.slashRowActive)}
            >
              <Slash size={13} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>/{cmd.name}</div>
                {cmd.description && (
                  <div
                    style={{
                      color: 'var(--lobe-color-text-tertiary)',
                      fontSize: 11.5,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {cmd.description}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {submitError && (
        <div role="status" style={{ color: 'var(--lobe-color-error)', fontSize: 12, paddingInline: 8 }}>
          {submitError}
        </div>
      )}
      <div data-pt-composer-card="1" {...sx(styles.card)}>
        {(pendingImages.length > 0 || pendingFiles.length > 0 || composerQuote.length > 0) && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {(pendingImages.length > 0 || pendingFiles.length > 0) && (
              <div {...sx(styles.attachStrip)}>
                {pendingImages.map((img, i) => (
                  <div key={`${img.path}-${i}`} {...sx(styles.imgChip)}>
                    {img.dataUrl ? (
                      <img
                        alt={img.name}
                        src={img.dataUrl}
                        style={{ height: '100%', objectFit: 'cover', width: '100%' }}
                      />
                    ) : null}
                    <button
                      onClick={() =>
                        void invokeNativeUI('removeAttachment', {
                          kind: 'image',
                          path: img.path,
                          surface,
                        })
                      }
                      type="button"
                      {...sx(styles.imgChipClose)}
                    >
                      <X size={10} />
                    </button>
                  </div>
                ))}

                {pendingFiles.map((filePath) => (
                  <div key={filePath} {...sx(styles.fileChip)}>
                    <FileText size={13} />
                    <span>{filePath.split('/').pop()}</span>
                    <button
                      onClick={() =>
                        void invokeNativeUI('removeAttachment', {
                          kind: 'file',
                          path: filePath,
                          surface,
                        })
                      }
                      style={{ background: 'none', border: 0, color: 'inherit', cursor: 'pointer', display: 'flex', padding: 0 }}
                      type="button"
                    >
                      <X size={12} />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {composerQuote && (
              <div {...sx(styles.quoteBanner)}>
                <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {composerQuote.replace(/^>\s*/gm, '')}
                </span>
                <button
                  onClick={() => setComposerQuote('')}
                  style={{ background: 'none', border: 0, color: 'inherit', cursor: 'pointer', padding: 0 }}
                  type="button"
                >
                  <X size={13} />
                </button>
              </div>
            )}
          </div>
        )}

        <textarea
          data-pt-composer-input="1"
          disabled={!selectedSessionId}
          onChange={(e) => handleDraftChange(e.target.value)}
          onCompositionEnd={() => {
            isComposingRef.current = false;
          }}
          onCompositionStart={() => {
            isComposingRef.current = true;
          }}
          onKeyDown={handleKeyDown}
          onPaste={handlePaste}
          placeholder={
            !selectedSessionId
              ? language === 'en'
                ? 'Choose a conversation to message Claude...'
                : '请先选择或新建一个会话…'
              : language === 'en'
                ? 'Ask, create, or start a task. Type / for Claude commands…'
                : '提问、创建或开始任务。输入 / 调用斜杠命令…'
          }
          ref={textareaRef}
          rows={1}
          value={draft}
          {...sx(styles.textarea)}
        />

        <div {...sx(styles.toolbar)}>
          <div {...sx(styles.toolbarLeft)}>
            <DropdownMenu items={attachMenuItems}>
              <ActionIcon
                data-pt-attach-btn="1"
                disabled={!selectedSessionId}
                icon={Plus}
                size="small"
                title={language === 'en' ? 'Add files or images' : '添加文件或图片'}
              />
            </DropdownMenu>
            <ActionIcon
              data-pt-slash-btn="1"
              disabled={!selectedSessionId}
              icon={Slash}
              onClick={() => {
                const next = draft.startsWith('/') ? draft : '/';
                handleDraftChange(next);
                textareaRef.current?.focus();
              }}
              size="small"
              title={language === 'en' ? 'Slash Commands (/)' : '斜杠命令菜单 (/)'}
            />
          </div>

          <div ref={popoverRef} {...sx(styles.toolbarRight)}>
            <button
              data-pt-model-trigger="1"
              disabled={!selectedSessionId}
              onClick={() => setModelPopoverOpen((v) => !v)}
              type="button"
              {...sx(styles.modelBtn)}
            >
              <span>{currentModel || (language === 'en' ? 'Model' : '模型')}</span>
              <span style={{ opacity: 0.7 }}>{currentEffort}</span>
              <ChevronDown size={13} />
            </button>

            {modelPopoverOpen && (
              <div data-pt-model-popover="1" {...sx(styles.popoverCard)}>
                <Input
                  allowClear
                  autoFocus
                  onChange={(e) => setModelFilter(e.target.value)}
                  placeholder={language === 'en' ? 'Search models...' : '搜索模型…'}
                  prefix={<Search size={13} />}
                  size="small"
                  value={modelFilter}
                />
                <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 11.5, paddingInline: 6 }}>
                  Anthropic
                </div>
                <div style={{ maxHeight: 210, overflowY: 'auto' }}>
                  {filteredModels.map((m) => {
                    const active = m.id === currentModel;
                    const switching = modelChange?.editorId === editorId && modelChange.model === m.id;
                    return (
                      <div
                        key={m.id}
                        onClick={() => void chooseModel(m.id)}
                        onKeyDown={(event) => {
                          if (event.key !== 'Enter' && event.key !== ' ') return;
                          event.preventDefault();
                          void chooseModel(m.id);
                        }}
                        role="button"
                        tabIndex={0}
                        {...sx(styles.modelItem, active && styles.modelItemActive)}
                      >
                        <div style={{ alignItems: 'center', display: 'flex', gap: 8 }}>
                          <Claude.Color size={15} />
                          <span>{m.id}</span>
                        </div>
                        {switching
                          ? <Loader2 className="pt-spin" size={14} />
                          : active && <Check color="#1677ff" size={14} />}
                      </div>
                    );
                  })}
                </div>

                <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 11.5, paddingInline: 4 }}>
                  {language === 'en' ? 'Reasoning Effort' : '推理强度'}
                </div>
                <div {...sx(styles.effortPills)}>
                  {efforts.map((level) => (
                    <button
                      key={level}
                      onClick={() => {
                        void invokeNativeUI('setEffort', { effort: level, sessionId: selectedSessionId });
                      }}
                      type="button"
                      {...sx(styles.effortChip, level === currentEffort && styles.effortChipActive)}
                    >
                      {level}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {isAwaiting ? (
              <button
                aria-label={language === 'en' ? 'Interrupt' : '停止生成'}
                data-pt-stop-btn="1"
                onClick={() => void invokeNativeUI('interruptOutput', { sessionId: selectedSessionId })}
                title={language === 'en' ? 'Stop Claude Code' : '中断输出'}
                type="button"
                {...sx(styles.stopBtn)}
              >
                <Square fill="currentColor" size={11} />
              </button>
            ) : (
              <button
                aria-label={language === 'en' ? 'Send' : '发送消息'}
                data-pt-send-btn="1"
                disabled={!canSubmit}
                onClick={() => void handleSubmit()}
                title={language === 'en' ? 'Send (Enter)' : '发送 (↩)'}
                type="button"
                {...sx(styles.sendBtn, !canSubmit && styles.sendBtnDisabled)}
              >
                <ArrowUp size={15} />
              </button>
            )}
          </div>
        </div>
      </div>

      {!compact && <ControlBar onOpenGitDir={onOpenGitDir} />}
    </div>
  );
});

ChatInput.displayName = 'ChatInput';
