import {
  ActionIcon,
  Button,
  Checkbox,
  CodeDiff,
  DropdownMenu,
  Input,
  PatchDiff,
  Tag,
  type DropdownItem,
} from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import { Virtualizer } from '@pierre/diffs/react';
import * as stylex from '@stylexjs/stylex';
import {
  ChevronDown,
  ChevronRight,
  Columns2,
  FileCode2,
  FolderPlus,
  GitBranch,
  GitCommit,
  RefreshCw,
  Rows2,
  Trash2,
} from 'lucide-react';
import { AnimatePresence } from 'motion/react';
import * as m from 'motion/react-m';
import { memo, useCallback, useMemo, useState } from 'react';

import type { GitReviewFile } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  root: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minHeight: 0,
    overflow: 'hidden',
  },
  header: {
    alignItems: 'center',
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
    justifyContent: 'space-between',
    paddingBlock: 8,
    paddingInline: 10,
    position: 'relative',
  },
  modeGroup: {
    alignItems: 'center',
    display: 'flex',
    gap: 4,
  },
  scroll: {
    flex: 1,
    minHeight: 0,
    overflowY: 'auto',
  },
  fileItem: {
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
  },
  fileRow: {
    alignItems: 'center',
    cursor: 'pointer',
    display: 'flex',
    fontSize: 12.5,
    gap: 6,
    paddingBlock: 7,
    paddingInline: 10,
    userSelect: 'none',
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
    },
  },
  diffWrap: {
    paddingBottom: 10,
    paddingInline: 8,
  },
  commitPopover: {
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    boxShadow: cssVar.boxShadowSecondary,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    padding: 12,
    position: 'absolute',
    right: 10,
    top: 44,
    width: 300,
    zIndex: 45,
  },
});

const ReviewFileRow = memo<{
  file: GitReviewFile;
  onOpenSource: (filePath: string) => void;
  openSourceLabel: string;
  viewMode: 'unified' | 'split';
}>(({ file, onOpenSource, openSourceLabel, viewMode }) => {
  const [expanded, setExpanded] = useState(true);
  const dotColor =
    file.statusCode === '??' || file.statusCode.includes('A')
      ? '#22c55e'
      : file.statusCode.includes('D')
        ? '#ef4444'
        : '#1677ff';

  return (
    <div {...sx(styles.fileItem)}>
      <div
        onClick={() => setExpanded((v) => !v)}
        role="button"
        tabIndex={0}
        {...sx(styles.fileRow)}
      >
        {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <span style={{ backgroundColor: dotColor, borderRadius: 99, height: 6, width: 6 }} />
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {file.path}
        </span>
        <Tag>{file.statusLabel}</Tag>
        {file.added > 0 && <span style={{ color: '#22c55e', fontSize: 11.5 }}>+{file.added}</span>}
        {file.removed > 0 && <span style={{ color: '#ef4444', fontSize: 11.5 }}>-{file.removed}</span>}
        <ActionIcon
          aria-label={openSourceLabel}
          data-pt-open-review-source={file.path}
          icon={FileCode2}
          onClick={(event) => {
            event.stopPropagation();
            onOpenSource(file.path);
          }}
          size="small"
          title={openSourceLabel}
        />
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
            <div {...sx(styles.diffWrap)}>
              {file.patch ? (
                <PatchDiff
                  defaultExpand
                  fileName={file.path}
                  fullFeatured={false}
                  patch={file.patch}
                  showHeader={false}
                  variant="borderless"
                  viewMode={viewMode}
                />
              ) : (
                <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12, paddingInline: 14 }}>
                  {file.binary ? 'Binary file' : 'No line diff available'}
                </div>
              )}
            </div>
          </m.div>
        )}
      </AnimatePresence>
    </div>
  );
});

ReviewFileRow.displayName = 'ReviewFileRow';

export const ReviewPane = memo(() => {
  const gitState = usePTSlice('gitState');
  const language = usePTSlice('language');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const activeTab = usePTSlice('activeTab');
  const [viewMode, setViewMode] = useState<'unified' | 'split'>('unified');
  const [commitPopoverOpen, setCommitPopoverOpen] = useState(false);
  const [commitMessage, setCommitMessage] = useState('');
  const [includeUnstaged, setIncludeUnstaged] = useState(true);

  const reviewMode = gitState.reviewMode ?? 'git';
  const directories = gitState.directories ?? [];
  const observed = gitState.observedDirectory || '';
  const openSourceLabel = language === 'en' ? 'Open source file' : '打开源文件';
  const openSource = useCallback((filePath: string) => {
    // Git paths are relative to the observed repository, which may differ from the session cwd.
    const resolvedPath = reviewMode === 'git' && observed && !filePath.startsWith('/')
      ? `${observed.replace(/\/$/, '')}/${filePath}`
      : filePath;
    void invokeNativeUI('openTranscriptFile', {
      filePath: resolvedPath,
      sessionId: selectedSessionId,
      tabId: activeTab?.id,
    });
  }, [activeTab?.id, observed, reviewMode, selectedSessionId]);
  const dirLabel = observed
    ? observed.split('/').filter(Boolean).pop() || observed
    : language === 'en'
      ? 'Pick Repo'
      : '选择目录';

  const dirItems = useMemo<DropdownItem[]>(() => {
    const list: DropdownItem[] = directories.map((d) => ({
      key: d,
      label: `${d === observed ? '✓ ' : ''}${d.split('/').filter(Boolean).pop() || d}`,
      onClick: () => {
        void invokeNativeUI('selectGitDirectory', { directory: d });
      },
    }));
    list.push({ type: 'divider' });
    list.push({
      icon: <FolderPlus size={14} />,
      key: 'add-dir',
      label: language === 'en' ? 'Add Git Directory...' : '选择 Git 观察目录…',
      onClick: () => {
        void invokeNativeUI('chooseGitDirectory', {});
      },
    });
    if (observed) {
      list.push({
        danger: true,
        icon: <Trash2 size={14} />,
        key: 'remove-dir',
        label: language === 'en' ? 'Remove Current Directory' : '从记忆列表移除此目录',
        onClick: () => {
          void invokeNativeUI('removeGitDirectory', { directory: observed });
        },
      });
    }
    return list;
  }, [directories, language, observed]);

  const handleGitAction = (commit: boolean, push: boolean) => {
    void invokeNativeUI('gitCommitAndPush', {
      commit,
      directory: observed,
      includeUnstaged,
      message: commitMessage,
      push,
    });
  };

  return (
    <div data-pt-review-pane="1" {...sx(styles.root)}>
      <div {...sx(styles.header)}>
        <div {...sx(styles.modeGroup)}>
          <Button
            onClick={() =>
              void invokeNativeUI('refreshGitReview', { directory: observed, mode: 'git' })
            }
            size="small"
            type={reviewMode === 'git' ? 'primary' : 'text'}
          >
            Git Diff
          </Button>
          <Button
            onClick={() =>
              void invokeNativeUI('refreshGitReview', {
                mode: 'turn',
                sessionId: selectedSessionId,
                turnIndex: gitState.turnIndex ?? 0,
              })
            }
            size="small"
            type={reviewMode === 'turn' ? 'primary' : 'text'}
          >
            {language === 'en' ? 'Turn Edits' : '本轮编辑'}
          </Button>
        </div>

        <div {...sx(styles.modeGroup)}>
          {reviewMode === 'git' && (
            <>
              <DropdownMenu items={dirItems}>
                <Button icon={<GitBranch size={12} />} size="small" type="default">
                  {dirLabel}
                </Button>
              </DropdownMenu>

              <ActionIcon
                icon={RefreshCw}
                onClick={() =>
                  void invokeNativeUI('refreshGitReview', { directory: observed, mode: 'git' })
                }
                size="small"
                title={language === 'en' ? 'Refresh diff' : '刷新 Diff'}
              />

              <ActionIcon
                disabled={!observed}
                icon={GitCommit}
                onClick={() => setCommitPopoverOpen((v) => !v)}
                size="small"
                title={language === 'en' ? 'Commit & Push' : '提交 / 推送'}
              />
            </>
          )}

          <ActionIcon
            aria-label={viewMode === 'unified' ? 'Split Diff' : 'Unified Diff'}
            icon={viewMode === 'unified' ? Columns2 : Rows2}
            onClick={() => setViewMode((m) => (m === 'unified' ? 'split' : 'unified'))}
            size="small"
            title={viewMode === 'unified' ? 'Split Diff' : 'Unified Diff'}
          />
        </div>

        {commitPopoverOpen && (
          <div {...sx(styles.commitPopover)}>
            <div style={{ alignItems: 'center', display: 'flex', fontSize: 12.5, fontWeight: 600, gap: 6 }}>
              <GitBranch size={13} />
              <span>{gitState.branch || 'HEAD'}</span>
            </div>
            <Input
              onChange={(e) => setCommitMessage(e.target.value)}
              placeholder={language === 'en' ? 'Commit message' : '输入提交说明…'}
              size="small"
              value={commitMessage}
            />
            <Checkbox
              checked={includeUnstaged}
              onChange={(checked) => setIncludeUnstaged(Boolean(checked))}
            >
              <span style={{ fontSize: 12 }}>
                {language === 'en' ? 'Include unstaged changes' : '包含未暂存更改'}
              </span>
            </Checkbox>
            <div style={{ display: 'flex', gap: 6 }}>
              <Button
                disabled={!commitMessage.trim() || gitState.actionInFlight}
                onClick={() => handleGitAction(true, false)}
                size="small"
                style={{ flex: 1 }}
                type="default"
              >
                {language === 'en' ? 'Commit' : '提交'}
              </Button>
              <Button
                disabled={!commitMessage.trim() || gitState.actionInFlight}
                loading={gitState.actionInFlight}
                onClick={() => handleGitAction(true, true)}
                size="small"
                style={{ flex: 1 }}
                type="primary"
              >
                {language === 'en' ? 'Commit & Push' : '提交并推送'}
              </Button>
              <Button
                disabled={gitState.actionInFlight}
                onClick={() => handleGitAction(false, true)}
                size="small"
                type="default"
              >
                Push
              </Button>
            </div>
            {gitState.actionStatus && (
              <div style={{ color: 'var(--lobe-color-text-secondary)', fontSize: 11.5 }}>
                {gitState.actionStatus}
              </div>
            )}
          </div>
        )}
      </div>

      <Virtualizer {...sx(styles.scroll, 'pt-diff-viewport')}>
        {reviewMode === 'turn' ? (
          (gitState.editEvents ?? []).length === 0 ? (
            <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12.5, padding: 24, textAlign: 'center' }}>
              {language === 'en' ? 'No recorded Edit / Write events in this turn' : '本轮对话暂无 Edit / Write 记录'}
            </div>
          ) : (
            (gitState.editEvents ?? []).map((ev, idx) => (
              <div key={`${ev.filePath}-${idx}`} {...sx(styles.fileItem)}>
                <div style={{ padding: 10 }}>
                  <div style={{ alignItems: 'center', display: 'flex', gap: 6, marginBottom: 6 }}>
                    <span style={{ flex: 1, fontSize: 12, fontWeight: 600, overflowWrap: 'anywhere' }}>{ev.filePath}</span>
                    <ActionIcon
                      aria-label={openSourceLabel}
                      data-pt-open-review-source={ev.filePath}
                      icon={FileCode2}
                      onClick={() => openSource(ev.filePath)}
                      size="small"
                      title={openSourceLabel}
                    />
                  </div>
                  <CodeDiff
                    defaultExpand
                    fileName={ev.filePath.split('/').pop() || 'file'}
                    fullFeatured={false}
                    newContent={ev.newText}
                    oldContent={ev.oldText}
                    showHeader={false}
                    variant="borderless"
                    viewMode={viewMode}
                  />
                </div>
              </div>
            ))
          )
        ) : gitState.error ? (
          <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12.5, padding: 24, textAlign: 'center' }}>
            {gitState.error}
          </div>
        ) : (gitState.files ?? []).length === 0 ? (
          <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12.5, padding: 24, textAlign: 'center' }}>
            {gitState.loading
              ? language === 'en'
                ? 'Loading git status & diff...'
                : '正在采集 Git 状态与改动…'
              : language === 'en'
                ? 'Working tree is clean'
                : '当前工作树干净，没有未提交修改'}
          </div>
        ) : (
          (gitState.files ?? []).map((file) => (
            <ReviewFileRow
              key={file.path}
              file={file}
              onOpenSource={openSource}
              openSourceLabel={openSourceLabel}
              viewMode={viewMode}
            />
          ))
        )}
      </Virtualizer>
    </div>
  );
});

ReviewPane.displayName = 'ReviewPane';
