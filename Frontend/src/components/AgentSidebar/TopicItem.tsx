import { ActionIcon, DropdownMenu, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  Clipboard,
  ExternalLink,
  FolderOpen,
  FolderSearch,
  Loader2,
  MoreHorizontal,
  Pencil,
  Send,
} from 'lucide-react';
import { memo, useMemo, useState } from 'react';

import type { SessionSummary, UILanguage } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  row: {
    alignItems: 'center',
    borderRadius: 8,
    boxSizing: 'border-box',
    color: cssVar.colorText,
    cursor: 'pointer',
    display: 'flex',
    gap: 8,
    height: 32,
    paddingInline: 8,
    position: 'relative',
    transition: 'background-color 0.12s ease',
    userSelect: 'none',
    width: '100%',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  rowActive: {
    backgroundColor: cssVar.colorFillTertiary,
    fontWeight: 500,
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
    },
  },
  indicator: {
    alignItems: 'center',
    color: cssVar.colorTextTertiary,
    display: 'flex',
    flexShrink: 0,
    justifyContent: 'center',
    width: 16,
  },
  dotLive: {
    backgroundColor: cssVar.colorSuccess,
    borderRadius: 99,
    height: 6,
    width: 6,
  },
  title: {
    color: cssVar.colorText,
    flex: 1,
    fontSize: 13,
    minWidth: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  titleInactive: {
    color: cssVar.colorTextSecondary,
  },
  actions: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    opacity: 0,
    transition: 'opacity 0.12s ease',
  },
  actionsVisible: {
    opacity: 1,
  },
});

export interface TopicItemProps {
  active: boolean;
  language: UILanguage;
  onRename: (session: SessionSummary) => void;
  onSelect: (sessionId: string) => void;
  session: SessionSummary;
}

export const TopicItem = memo<TopicItemProps>(
  ({ active, language, onRename, onSelect, session }) => {
    const [hovered, setHovered] = useState(false);

    const isWorking = Boolean(session.responding || session.awaitingReply);
    const isRunning = Boolean(session.running);
    const title = session.title || (language === 'en' ? 'Untitled Conversation' : '未命名对话');

    const menuItems = useMemo<DropdownItem[]>(
      () => [
        {
          icon: <Pencil size={14} />,
          key: 'rename',
          label: language === 'en' ? 'Rename' : '重命名',
          onClick: () => onRename(session),
        },
        {
          icon: <ExternalLink size={14} />,
          key: 'new-tab',
          label: language === 'en' ? 'Open in New Tab' : '在新标签页打开',
          onClick: () => {
            void invokeNativeUI('selectSession', { newTab: true, sessionId: session.sessionId });
          },
        },
        { type: 'divider' },
        {
          disabled: !session.filePath,
          icon: <FolderSearch size={14} />,
          key: 'reveal',
          label: language === 'en' ? 'Reveal in Finder' : '在 Finder 中显示',
          onClick: () => {
            void invokeNativeUI('revealSessionTranscript', { sessionId: session.sessionId });
          },
        },
        {
          disabled: !session.cwd,
          icon: <FolderOpen size={14} />,
          key: 'open-folder',
          label: language === 'en' ? 'Open Project Folder' : '打开项目目录',
          onClick: () => {
            void invokeNativeUI('openProjectFolder', {
              path: session.cwd,
              sessionId: session.sessionId,
            });
          },
        },
        {
          disabled: !session.filePath,
          icon: <Clipboard size={14} />,
          key: 'copy-path',
          label: language === 'en' ? 'Copy Transcript Path' : '拷贝 transcript 路径',
          onClick: () => {
            void invokeNativeUI('copyText', {
              label: language === 'en' ? 'Transcript path copied' : '已拷贝 transcript 路径',
              text: session.filePath,
            });
          },
        },
      ],
      [language, onRename, session],
    );

    return (
      <div
        data-pt-session-id={session.sessionId}
        onClick={() => onSelect(session.sessionId)}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            onSelect(session.sessionId);
          }
        }}
        title={`${title}\n${session.cwd || ''}`}
        {...sx(styles.row, active && styles.rowActive)}
      >
        {(isWorking || isRunning) && (
          <span {...sx(styles.indicator)}>
            {isWorking ? (
              <Loader2 className="pt-spin" size={13} />
            ) : isRunning ? (
              <span {...sx(styles.dotLive)} />
            ) : (
              <Send size={12} />
            )}
          </span>
        )}
        <span {...sx(styles.title, !active && styles.titleInactive)}>{title}</span>
        <div
          onClick={(e) => e.stopPropagation()}
          {...sx(styles.actions, (hovered || active) && styles.actionsVisible)}
        >
          <DropdownMenu items={menuItems}>
            <ActionIcon icon={MoreHorizontal} size="small" />
          </DropdownMenu>
        </div>
      </div>
    );
  },
);

TopicItem.displayName = 'TopicItem';
