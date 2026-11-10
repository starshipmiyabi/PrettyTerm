import Claude from '@lobehub/icons/es/Claude';
import { ActionIcon, DropdownMenu, Input, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  Calendar,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  FolderOpen,
  FolderTree,
  Globe,
  HelpCircle,
  LayoutList,
  MessageSquare,
  MessageSquarePlus,
  RefreshCw,
  Search,
  Settings,
  SquareTerminal,
} from 'lucide-react';
import { AnimatePresence } from 'motion/react';
import * as m from 'motion/react-m';
import { memo, useMemo, useState } from 'react';

import type { SessionSummary, WorkingTabKind } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

import { TopicItem } from './TopicItem';

const styles = stylex.create({
  sidebarOuter: {
    boxSizing: 'border-box',
    display: 'flex',
    flexDirection: 'column',
    flexShrink: 0,
    height: '100%',
    overflow: 'hidden',
    userSelect: 'none',
  },
  inner: {
    boxSizing: 'border-box',
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minHeight: 0,
    paddingBottom: 10,
    paddingInline: 8,
    paddingTop: 4,
    width: 248,
  },
  brandRow: {
    alignItems: 'center',
    borderRadius: 8,
    display: 'flex',
    gap: 8,
    height: 36,
    paddingInline: 6,
  },
  brandTrigger: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 8,
    borderWidth: 0,
    color: cssVar.colorText,
    cursor: 'pointer',
    display: 'flex',
    flex: 1,
    fontSize: 13.5,
    fontWeight: 600,
    gap: 8,
    minWidth: 0,
    paddingBlock: 4,
    paddingInline: 6,
    textAlign: 'left',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  navSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 1,
    marginTop: 4,
  },
  navBtn: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 8,
    borderWidth: 0,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 13,
    fontWeight: 500,
    gap: 9,
    height: 34,
    paddingInline: 10,
    textAlign: 'left',
    width: '100%',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
      color: cssVar.colorText,
    },
  },
  searchBox: {
    paddingBlock: 6,
    paddingInline: 2,
  },
  topicHeader: {
    alignItems: 'center',
    color: cssVar.colorTextTertiary,
    display: 'flex',
    fontSize: 12,
    fontWeight: 500,
    justifyContent: 'space-between',
    marginTop: 10,
    paddingBottom: 4,
    paddingInline: 8,
  },
  topicHeaderLeft: {
    alignItems: 'center',
    display: 'flex',
    gap: 4,
  },
  topicScroll: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    gap: 1,
    minHeight: 0,
    overflowY: 'auto',
    paddingRight: 2,
  },
  groupTitle: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderWidth: 0,
    color: cssVar.colorTextTertiary,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 11.5,
    fontWeight: 500,
    gap: 4,
    marginTop: 8,
    paddingBlock: 4,
    paddingInline: 8,
    textAlign: 'left',
    width: '100%',
    ':hover': {
      color: cssVar.colorTextSecondary,
    },
  },
  groupTitleText: {
    flex: 1,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  groupCount: {
    color: cssVar.colorTextQuaternary,
    fontSize: 11,
  },
  emptyHint: {
    color: cssVar.colorTextTertiary,
    fontSize: 12,
    paddingBlock: 18,
    paddingInline: 10,
    textAlign: 'center',
  },
  footerWrap: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    marginTop: 6,
  },
  sourceCard: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 10,
    borderStyle: 'solid',
    borderWidth: 1,
    display: 'flex',
    gap: 8,
    justifyContent: 'space-between',
    paddingBlock: 8,
    paddingInline: 10,
  },
  sourceTitle: {
    color: cssVar.colorTextSecondary,
    fontSize: 11.5,
    fontWeight: 500,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  sourceAction: {
    color: cssVar.colorPrimary,
    cursor: 'pointer',
    fontSize: 11.5,
    fontWeight: 500,
  },
  bottomIcons: {
    alignItems: 'center',
    display: 'flex',
    gap: 2,
    justifyContent: 'space-between',
    paddingInline: 4,
  },
  versionText: {
    color: cssVar.colorTextQuaternary,
    fontSize: 11,
  },
});

interface SessionGroup {
  items: SessionSummary[];
  key: string;
  label: string;
}

function getTimeBucket(ms: number, lang: 'zh-Hans' | 'en'): { key: string; label: string } {
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const weekAgo = startOfToday - 6 * 86_400_000;
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  if (ms >= startOfToday) {
    return { key: 'today', label: lang === 'en' ? 'Today' : '今天' };
  }
  if (ms >= weekAgo) {
    return { key: 'week', label: lang === 'en' ? 'This Week' : '本周' };
  }
  if (ms >= monthStart) {
    return { key: 'month', label: lang === 'en' ? 'This Month' : '本月' };
  }
  const dt = new Date(ms || Date.now());
  const monthLabel =
    lang === 'en'
      ? dt.toLocaleDateString('en-US', { month: 'short', year: 'numeric' })
      : `${dt.getFullYear()}年${dt.getMonth() + 1}月`;
  return { key: `${dt.getFullYear()}-${dt.getMonth() + 1}`, label: monthLabel };
}

export interface AgentSidebarProps {
  onOpenNewChat: () => void;
  onOpenWorkingTab: (tab: WorkingTabKind) => void;
}

export const AgentSidebar = memo<AgentSidebarProps>(({ onOpenNewChat, onOpenWorkingTab }) => {
  const groupMode = usePTSlice('groupMode');
  const language = usePTSlice('language');
  const searchQuery = usePTSlice('searchQuery');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const sessions = usePTSlice('sessions');
  const setGroupMode = usePTSlice('setGroupMode');
  const setRenameModalSession = usePTSlice('setRenameModalSession');
  const setSearchQuery = usePTSlice('setSearchQuery');
  const setSidebarCollapsed = usePTSlice('setSidebarCollapsed');
  const setTerminalOpen = usePTSlice('setTerminalOpen');
  const sidebarCollapsed = usePTSlice('sidebarCollapsed');
  const windowState = usePTSlice('windowState');

  const [searchOpen, setSearchOpen] = useState(false);
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});

  const filteredSessions = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return sessions;
    return sessions.filter((s) =>
      `${s.title} ${s.cwd} ${s.projectTitle}`.toLowerCase().includes(q),
    );
  }, [searchQuery, sessions]);

  const groups = useMemo<SessionGroup[]>(() => {
    const ordered: SessionGroup[] = [];
    const byKey = new Map<string, SessionGroup>();
    for (const s of filteredSessions) {
      const bucket =
        groupMode === 'project'
          ? { key: s.projectKey || s.cwd || 'unknown', label: s.projectTitle || '未命名项目' }
          : getTimeBucket(s.modifiedAtMs, language);
      let g = byKey.get(bucket.key);
      if (!g) {
        g = { items: [], key: bucket.key, label: bucket.label };
        byKey.set(bucket.key, g);
        ordered.push(g);
      }
      g.items.push(s);
    }
    return ordered;
  }, [filteredSessions, groupMode, language]);

  const toggleGroup = (key: string) => {
    setCollapsedGroups((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const settingsMenu = useMemo<DropdownItem[]>(
    () => [
      {
        icon: <Globe size={14} />,
        key: 'lang',
        label: language === 'en' ? '切换为简体中文' : 'Switch to English',
        onClick: () => {
          void invokeNativeUI('setLanguage', {
            language: language === 'en' ? 'zh-Hans' : 'en',
          });
        },
      },
      {
        icon: <SquareTerminal size={14} />,
        key: 'terminal',
        label: language === 'en' ? 'Toggle Terminal Drawer' : '打开 / 收起底部终端',
        onClick: () => setTerminalOpen((v) => !v),
      },
      { type: 'divider' },
      {
        icon: <FolderOpen size={14} />,
        key: 'reveal-projects',
        label: language === 'en' ? 'Open ~/.claude/projects' : '在 Finder 打开会话目录',
        onClick: () => {
          void invokeNativeUI('openProjectsRoot', {});
        },
      },
    ],
    [language, setTerminalOpen],
  );

  return (
    <m.aside
      animate={{
        opacity: sidebarCollapsed ? 0 : 1,
        width: sidebarCollapsed ? 0 : 248,
      }}
      data-pt-sidebar="1"
      initial={false}
      transition={{ duration: 0.2, ease: [0.32, 0.72, 0, 1] }}
      {...sx(styles.sidebarOuter)}
    >
      <div {...sx(styles.inner)}>
        <div {...sx(styles.brandRow)}>
          <ActionIcon
            icon={ChevronLeft}
            onClick={() => setSidebarCollapsed(true)}
            size="small"
            title={language === 'en' ? 'Collapse Sidebar' : '收起侧边栏'}
          />
          <button
            onClick={() => {
              setSearchOpen(false);
              setSearchQuery('');
            }}
            type="button"
            {...sx(styles.brandTrigger)}
          >
            <Claude.Color size={18} />
            <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              Claude Code
            </span>
          </button>
          <ActionIcon
            data-pt-refresh-btn="1"
            icon={RefreshCw}
            onClick={() => void invokeNativeUI('refreshSessions', {})}
            size="small"
            title={language === 'en' ? 'Refresh sessions' : '刷新本地会话'}
          />
        </div>

        <nav {...sx(styles.navSection)}>
          <button
            data-pt-new-chat-btn="1"
            onClick={onOpenNewChat}
            type="button"
            {...sx(styles.navBtn)}
          >
            <MessageSquarePlus size={15} />
            <span>{language === 'en' ? 'New Conversation' : '开启新话题'}</span>
          </button>

          <button
            data-pt-search-toggle-btn="1"
            onClick={() => setSearchOpen((v) => !v)}
            type="button"
            {...sx(styles.navBtn)}
          >
            <Search size={15} />
            <span>{language === 'en' ? 'Search' : '搜索'}</span>
          </button>

          <button
            onClick={() => {
              setSearchOpen(false);
              setSearchQuery('');
            }}
            type="button"
            {...sx(styles.navBtn)}
          >
            <MessageSquare size={15} />
            <span>{language === 'en' ? 'Topics' : '话题'}</span>
          </button>

          <button
            onClick={() => onOpenWorkingTab('file')}
            type="button"
            {...sx(styles.navBtn)}
          >
            <FolderOpen size={15} />
            <span>{language === 'en' ? 'Files' : '文件工作区'}</span>
          </button>

          <button
            onClick={() => onOpenWorkingTab('tasks')}
            type="button"
            {...sx(styles.navBtn)}
          >
            <LayoutList size={15} />
            <span>{language === 'en' ? 'Tasks & Review' : '任务与审查'}</span>
          </button>
        </nav>

        <AnimatePresence initial={false}>
          {searchOpen && (
            <m.div
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              initial={{ height: 0, opacity: 0 }}
              style={{ overflow: 'hidden' }}
              transition={{ duration: 0.16 }}
            >
              <div {...sx(styles.searchBox)}>
                <Input
                  allowClear
                  autoFocus
                  data-pt-sidebar-search="1"
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder={language === 'en' ? 'Search topics or project...' : '搜索会话或目录...'}
                  prefix={<Search size={13} />}
                  size="small"
                  value={searchQuery}
                />
              </div>
            </m.div>
          )}
        </AnimatePresence>

        <div {...sx(styles.topicHeader)}>
          <div {...sx(styles.topicHeaderLeft)}>
            <span>
              {language === 'en' ? `Topics ${filteredSessions.length}` : `话题 ${filteredSessions.length}`}
            </span>
          </div>
          <ActionIcon
            data-pt-group-mode-btn="1"
            icon={groupMode === 'time' ? FolderTree : Calendar}
            onClick={() => setGroupMode(groupMode === 'time' ? 'project' : 'time')}
            size="small"
            title={
              groupMode === 'time'
                ? language === 'en'
                  ? 'Group by project'
                  : '切换按项目分组'
                : language === 'en'
                  ? 'Group by time'
                  : '切换按时间分组'
            }
          />
        </div>

        <div data-pt-topic-list="1" {...sx(styles.topicScroll)}>
          {groups.length === 0 ? (
            <div {...sx(styles.emptyHint)}>
              {searchQuery.trim()
                ? language === 'en'
                  ? 'No matching conversations'
                  : '没有匹配的会话'
                : language === 'en'
                  ? 'No local sessions yet'
                  : '暂无本地会话'}
            </div>
          ) : (
            groups.map((group) => {
              const isCollapsed = !searchQuery.trim() && Boolean(collapsedGroups[group.key]);
              return (
                <div key={group.key}>
                  <button
                    onClick={() => toggleGroup(group.key)}
                    type="button"
                    {...sx(styles.groupTitle)}
                  >
                    <span {...sx(styles.groupTitleText)}>{group.label}</span>
                    <span {...sx(styles.groupCount)}>{group.items.length}</span>
                    {isCollapsed ? <ChevronRight size={12} /> : <ChevronDown size={12} />}
                  </button>
                  {!isCollapsed &&
                    group.items.map((session) => (
                      <TopicItem
                        key={session.sessionId}
                        active={session.sessionId === selectedSessionId}
                        language={language}
                        onRename={setRenameModalSession}
                        onSelect={(sessionId) => {
                          void invokeNativeUI('selectSession', { sessionId });
                        }}
                        session={session}
                      />
                    ))}
                </div>
              );
            })
          )}
        </div>

        <div {...sx(styles.footerWrap)}>
          <div {...sx(styles.sourceCard)}>
            <span {...sx(styles.sourceTitle)} title="~/.claude/projects">
              ~/.claude/projects
            </span>
            <span
              onClick={() => void invokeNativeUI('refreshSessions', {})}
              role="button"
              tabIndex={0}
              {...sx(styles.sourceAction)}
            >
              {language === 'en' ? 'Sync' : '刷新'}
            </span>
          </div>

          <div {...sx(styles.bottomIcons)}>
            <div style={{ alignItems: 'center', display: 'flex', gap: 2 }}>
              <ActionIcon
                icon={HelpCircle}
                onClick={() => void invokeNativeUI('openProjectsRoot', {})}
                size="small"
                title="~/.claude/projects"
              />
              <DropdownMenu items={settingsMenu}>
                <ActionIcon
                  icon={Settings}
                  size="small"
                  title={language === 'en' ? 'Settings' : '设置'}
                />
              </DropdownMenu>
            </div>
            <span {...sx(styles.versionText)}>v{windowState.version || '1.0.0'}</span>
          </div>
        </div>
      </div>
    </m.aside>
  );
});

AgentSidebar.displayName = 'AgentSidebar';
