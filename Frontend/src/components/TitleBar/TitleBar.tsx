import { ActionIcon, DropdownMenu, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  ArrowLeft,
  ArrowRight,
  Clock,
  Languages,
  PanelLeft,
  PictureInPicture2,
  SquareTerminal,
} from 'lucide-react';
import { memo, useMemo } from 'react';

import { invokeNativeUI, triggerWindowDrag } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

import { TabBar } from './TabBar';

const styles = stylex.create({
  bar: {
    alignItems: 'center',
    backgroundColor: cssVar.colorBgLayout,
    boxSizing: 'border-box',
    display: 'flex',
    flexShrink: 0,
    gap: 8,
    height: 44,
    paddingLeft: 76,
    paddingRight: 12,
    userSelect: 'none',
    width: '100%',
  },
  navGroup: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: 2,
  },
  dragSpacer: {
    flexShrink: 0,
    height: '100%',
    minWidth: 16,
  },
  rightCluster: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: 4,
    marginLeft: 'auto',
  },
  statusBadge: {
    alignItems: 'center',
    borderRadius: 99,
    color: cssVar.colorTextSecondary,
    display: 'flex',
    fontSize: 11.5,
    gap: 5,
    paddingBlock: 3,
    paddingInline: 8,
  },
  statusDot: {
    backgroundColor: cssVar.colorTextTertiary,
    borderRadius: 99,
    height: 6,
    width: 6,
  },
  statusDotOnline: {
    backgroundColor: cssVar.colorSuccess,
  },
});

export interface TitleBarProps {
  canGoBack: boolean;
  canGoForward: boolean;
  onGoBack: () => void;
  onGoForward: () => void;
}

export const TitleBar = memo<TitleBarProps>(
  ({ canGoBack, canGoForward, onGoBack, onGoForward }) => {
    const activeSession = usePTSlice('activeSession');
    const activeTab = usePTSlice('activeTab');
    const language = usePTSlice('language');
    const sessions = usePTSlice('sessions');
    const setSidebarCollapsed = usePTSlice('setSidebarCollapsed');
    const setTerminalOpen = usePTSlice('setTerminalOpen');
    const sidebarCollapsed = usePTSlice('sidebarCollapsed');
    const terminalOpen = usePTSlice('terminalOpen');
    const workspace = usePTSlice('workspace');

    const recentHistoryItems = useMemo<DropdownItem[]>(() => {
      return sessions.slice(0, 12).map((s) => ({
        key: s.sessionId,
        label: s.title || s.sessionId.slice(0, 8),
        onClick: () => {
          void invokeNativeUI('selectSession', { sessionId: s.sessionId });
        },
      }));
    }, [sessions]);

    const handleMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
      if (e.button !== 0) return;
      const target = e.target as HTMLElement | null;
      if (
        target?.closest('button, [role="button"], a, input, textarea, [data-tab-item="1"]')
      ) {
        return;
      }
      triggerWindowDrag('main');
    };

    const isConnected = Boolean(activeTab?.running || activeSession?.connected);

    return (
      <header data-pt-titlebar="1" onMouseDown={handleMouseDown} {...sx(styles.bar)}>
        <div {...sx(styles.navGroup)}>
          <ActionIcon
            active={!sidebarCollapsed}
            data-pt-sidebar-toggle="1"
            icon={PanelLeft}
            onClick={() => setSidebarCollapsed((v) => !v)}
            size="small"
            title={language === 'en' ? 'Toggle Sidebar (⌘B)' : '展开 / 收起侧边栏 (⌘B)'}
          />
          <ActionIcon
            disabled={!canGoBack}
            icon={ArrowLeft}
            onClick={onGoBack}
            size="small"
            title={language === 'en' ? 'Back' : '后退'}
          />
          <ActionIcon
            disabled={!canGoForward}
            icon={ArrowRight}
            onClick={onGoForward}
            size="small"
            title={language === 'en' ? 'Forward' : '前进'}
          />
          <DropdownMenu items={recentHistoryItems}>
            <ActionIcon
              icon={Clock}
              size="small"
              title={language === 'en' ? 'Recent conversations' : '最近对话历史'}
            />
          </DropdownMenu>
        </div>

        <TabBar />

        <div {...sx(styles.dragSpacer)} />

        <div {...sx(styles.rightCluster)}>
          <div
            title={
              isConnected
                ? language === 'en'
                  ? 'Claude session connected'
                  : 'Claude 后台会话已连接'
                : language === 'en'
                  ? 'Idle (read-only transcript)'
                  : '只读同步本地记录'
            }
            {...sx(styles.statusBadge)}
          >
            <span {...sx(styles.statusDot, isConnected && styles.statusDotOnline)} />
          </div>

          <ActionIcon
            active={terminalOpen}
            data-pt-terminal-toggle="1"
            icon={SquareTerminal}
            onClick={() => setTerminalOpen((v) => !v)}
            size="small"
            title={language === 'en' ? 'Toggle Terminal Drawer' : '打开 / 收起终端抽屉'}
          />

          <ActionIcon
            active={workspace.floatingVisible}
            data-pt-floating-toggle="1"
            disabled={!activeSession}
            icon={PictureInPicture2}
            onClick={() => {
              if (activeSession) {
                void invokeNativeUI('toggleFloatingWindow', { sessionId: activeSession.sessionId });
              }
            }}
            size="small"
            title={language === 'en' ? 'Toggle Floating Window (⌘O)' : '悬浮当前对话 (⌘O)'}
          />

          <ActionIcon
            data-pt-lang-toggle="1"
            icon={Languages}
            onClick={() => {
              void invokeNativeUI('setLanguage', {
                language: language === 'en' ? 'zh-Hans' : 'en',
              });
            }}
            size="small"
            title={language === 'en' ? '切换到中文' : 'Switch to English'}
          />
        </div>
      </header>
    );
  },
);

TitleBar.displayName = 'TitleBar';
