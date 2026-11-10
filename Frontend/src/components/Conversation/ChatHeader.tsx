import { ActionIcon, Button, DropdownMenu, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  FolderOpen,
  FolderTree,
  GitPullRequest,
  LayoutGrid,
  Minimize2,
  MoreHorizontal,
  PanelRight,
  Pin,
  PinOff,
  Radio,
  RefreshCw,
} from 'lucide-react';
import { memo, useMemo } from 'react';

import type { WorkingTabKind } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  header: {
    alignItems: 'center',
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    boxSizing: 'border-box',
    display: 'flex',
    flexShrink: 0,
    gap: 10,
    height: 46,
    justifyContent: 'space-between',
    paddingInline: 16,
  },
  left: {
    alignItems: 'center',
    display: 'flex',
    flex: 1,
    gap: 6,
    minWidth: 0,
  },
  title: {
    color: cssVar.colorText,
    fontSize: 14,
    fontWeight: 600,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  right: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: 4,
  },
  iconActive: {
    borderColor: cssVar.colorPrimary,
    borderRadius: 8,
    borderStyle: 'solid',
    borderWidth: 1.5,
  },
});

export interface ChatHeaderProps {
  onSelectWorkingTab: (tab: WorkingTabKind) => void;
  onToggleOverview: () => void;
  onTogglePanel: () => void;
  overviewActive: boolean;
  panelOpen: boolean;
  panelTab: WorkingTabKind;
}

export const ChatHeader = memo<ChatHeaderProps>(
  ({
    onSelectWorkingTab,
    onToggleOverview,
    onTogglePanel,
    overviewActive,
    panelOpen,
    panelTab,
  }) => {
    const activeSession = usePTSlice('activeSession');
    const activeTab = usePTSlice('activeTab');
    const language = usePTSlice('language');
    const transcript = usePTSlice('transcript');
    const workspace = usePTSlice('workspace');
    const sessionId = activeSession?.sessionId || transcript.sessionId || '';
    const title =
      activeSession?.title ||
      transcript.title ||
      (language === 'en' ? 'Select or Start a Conversation' : '选择或开启 Claude 对话');

    const isConnected = Boolean(activeTab?.running || activeSession?.connected);
    const isConnecting = Boolean(activeTab?.connecting);
    const isFloatingThis =
      workspace.floatingVisible && Boolean(sessionId) && workspace.floatingSessionId === sessionId;

    const moreItems = useMemo<DropdownItem[]>(
      () => [
        {
          disabled: !sessionId,
          icon: <Radio size={14} />,
          key: 'remote',
          label: 'Remote Control',
          onClick: () => {
            void invokeNativeUI('toggleRemoteControl', { sessionId });
          },
        },
        {
          disabled: !sessionId,
          icon: <Minimize2 size={14} />,
          key: 'compact',
          label: language === 'en' ? 'Compact Context (/compact)' : '压缩上下文 (/compact)',
          onClick: () => {
            void invokeNativeUI('sendCompact', { sessionId });
          },
        },
        {
          disabled: !sessionId,
          icon: <RefreshCw size={14} />,
          key: 'resync',
          label: language === 'en' ? 'Force Resync JSONL' : '重新解析当前 JSONL',
          onClick: () => {
            void invokeNativeUI('forceResyncSession', { sessionId });
          },
        },
        { type: 'divider' },
        {
          disabled: !activeSession?.cwd,
          icon: <FolderOpen size={14} />,
          key: 'open-folder',
          label: language === 'en' ? 'Open Working Directory' : '打开工作目录',
          onClick: () => {
            if (activeSession?.cwd) {
              void invokeNativeUI('openProjectFolder', { path: activeSession.cwd, sessionId });
            }
          },
        },
      ],
      [activeSession?.cwd, language, sessionId],
    );

    return (
      <div data-pt-chat-header="1" {...sx(styles.header)}>
        <div {...sx(styles.left)}>
          <span data-pt-conversation-title="1" {...sx(styles.title)} title={title}>
            {title}
          </span>
          <DropdownMenu items={moreItems}>
            <ActionIcon icon={MoreHorizontal} size="small" />
          </DropdownMenu>
        </div>

        <div {...sx(styles.right)}>
          {sessionId && (
            <Button
              data-pt-connect-btn="1"
              loading={isConnecting}
              onClick={() => {
                void invokeNativeUI(isConnected ? 'disconnectClaude' : 'connectClaude', { sessionId });
              }}
              size="small"
              type={isConnected ? 'default' : 'primary'}
            >
              {isConnecting
                ? language === 'en'
                  ? 'Syncing...'
                  : '正在同步…'
                : isConnected
                  ? language === 'en'
                    ? 'Synced'
                    : '已同步'
                  : language === 'en'
                    ? 'Connect'
                    : '连接 Claude'}
            </Button>
          )}

          <ActionIcon
            active={isFloatingThis}
            disabled={!sessionId}
            icon={isFloatingThis ? PinOff : Pin}
            onClick={() => {
              if (sessionId) void invokeNativeUI('toggleFloatingWindow', { sessionId });
            }}
            size="small"
            title={language === 'en' ? 'Float Window (⌘O)' : '悬浮当前对话 (⌘O)'}
          />

          <ActionIcon
            active={panelOpen && panelTab === 'file'}
            data-pt-header-files="1"
            icon={FolderTree}
            onClick={() => onSelectWorkingTab('file')}
            size="small"
            title={language === 'en' ? 'Files Workspace' : '文件工作区'}
          />

          <ActionIcon
            active={panelOpen && panelTab === 'review'}
            data-pt-header-review="1"
            icon={GitPullRequest}
            onClick={() => onSelectWorkingTab('review')}
            size="small"
            title={language === 'en' ? 'Git Review & Turn Changes' : 'Git Diff 与本轮审查'}
          />

          <div {...sx(overviewActive && !panelOpen && styles.iconActive)}>
            <ActionIcon
              active={overviewActive && !panelOpen}
              data-pt-header-overview="1"
              icon={LayoutGrid}
              onClick={onToggleOverview}
              size="small"
              title={language === 'en' ? 'Workspace Overview' : '工作区概览'}
            />
          </div>

          <ActionIcon
            active={panelOpen}
            data-pt-header-panel="1"
            icon={PanelRight}
            onClick={onTogglePanel}
            size="small"
            title={language === 'en' ? 'Toggle Right Panel' : '展开 / 收起工作面板'}
          />
        </div>
      </div>
    );
  },
);

ChatHeader.displayName = 'ChatHeader';
