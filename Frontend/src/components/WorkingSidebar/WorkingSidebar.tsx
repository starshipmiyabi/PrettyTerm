import { ActionIcon } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  CheckCircle2,
  Circle,
  ClipboardList,
  Files,
  GitPullRequest,
  LayoutGrid,
  Loader2,
  PanelRightClose,
} from 'lucide-react';
import { lazy, memo, Suspense, useCallback, useEffect, useRef, useState } from 'react';

import type { WorkingTabKind } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import {
  AUTO_COLLAPSE_HOST_WIDTH,
  clampWorkingPanelWidth,
  COLLAPSE_DRAG_THRESHOLD,
  OVERVIEW_PANEL_WIDTH,
} from '@/upstream/layout/workingLayout';
import { sx } from '@/upstream/styles/sx';

import { ClaudeTaskList } from './ClaudeTaskList';
import { OverviewPane } from './OverviewPane';

const FilesPane = lazy(() => import('./FilesPane').then(({ FilesPane }) => ({ default: FilesPane })));
const ReviewPane = lazy(() => import('./ReviewPane').then(({ ReviewPane }) => ({ default: ReviewPane })));

const styles = stylex.create({
  asideWrap: {
    display: 'flex',
    flexShrink: 0,
    height: '100%',
    overflow: 'hidden',
    position: 'relative',
  },
  divider: {
    cursor: 'col-resize',
    height: '100%',
    position: 'relative',
    width: 6,
    zIndex: 10,
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
    },
  },
  panel: {
    backgroundColor: cssVar.colorBgContainer,
    borderLeftColor: cssVar.colorBorderSecondary,
    borderLeftStyle: 'solid',
    borderLeftWidth: 1,
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    height: '100%',
    minWidth: 0,
    overflow: 'hidden',
  },
  tabsBar: {
    alignItems: 'center',
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexShrink: 0,
    gap: 4,
    height: 46,
    justifyContent: 'space-between',
    paddingInline: 10,
  },
  tabsLeft: {
    alignItems: 'center',
    display: 'flex',
    gap: 2,
  },
  tabChip: {
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
    paddingInline: 9,
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
      color: cssVar.colorText,
    },
  },
  tabChipActive: {
    backgroundColor: cssVar.colorFillTertiary,
    color: cssVar.colorText,
  },
  taskScroll: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    gap: 8,
    overflowY: 'auto',
    padding: 14,
  },
  taskCard: {
    alignItems: 'flex-start',
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 10,
    borderStyle: 'solid',
    borderWidth: 1,
    display: 'flex',
    gap: 8,
    paddingBlock: 9,
    paddingInline: 12,
  },
});

export interface WorkingSidebarProps {
  activeTab: WorkingTabKind;
  onChangeTab: (tab: WorkingTabKind) => void;
  onClose: () => void;
  onToggleTerminal: () => void;
  overviewOnly: boolean;
  panelOpen: boolean;
  width: number;
  onWidthChange: (w: number) => void;
}

export const WorkingSidebar = memo<WorkingSidebarProps>(
  ({ activeTab, onChangeTab, onClose, onToggleTerminal, onWidthChange, overviewOnly, panelOpen, width }) => {
    const activeSession = usePTSlice('activeSession');
    const sessionId = usePTSlice('selectedSessionId');
    const tabId = usePTSlice('activeTab')?.id;
    const language = usePTSlice('language');
    const draggingRef = useRef(false);
    const [narrowCollapsed, setNarrowCollapsed] = useState(() => window.innerWidth < AUTO_COLLAPSE_HOST_WIDTH);

    useEffect(() => {
      const checkWidth = () => {
        setNarrowCollapsed(window.innerWidth < AUTO_COLLAPSE_HOST_WIDTH);
      };
      checkWidth();
      window.addEventListener('resize', checkWidth);
      return () => window.removeEventListener('resize', checkWidth);
    }, []);

    useEffect(() => {
      if (!tabId || !panelOpen || narrowCollapsed || activeTab !== 'review') return;
      void invokeNativeUI('setReviewVisible', { tabId, visible: true });
      return () => { void invokeNativeUI('setReviewVisible', { tabId, visible: false }); };
    }, [activeTab, narrowCollapsed, panelOpen, tabId]);

    const handleDividerMouseDown = useCallback(
      (e: React.MouseEvent) => {
        if (overviewOnly) return;
        e.preventDefault();
        draggingRef.current = true;
        const startX = e.clientX;
        const startWidth = width;

        const onMove = (moveEvt: MouseEvent) => {
          if (!draggingRef.current) return;
          const next = startWidth + (startX - moveEvt.clientX);
          if (next < COLLAPSE_DRAG_THRESHOLD - 40) {
            draggingRef.current = false;
            onClose();
            window.removeEventListener('mousemove', onMove);
            window.removeEventListener('mouseup', onUp);
            return;
          }
          onWidthChange(clampWorkingPanelWidth(next));
        };

        const onUp = () => {
          draggingRef.current = false;
          window.removeEventListener('mousemove', onMove);
          window.removeEventListener('mouseup', onUp);
        };

        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
      },
      [onClose, onWidthChange, overviewOnly, width],
    );

    if (narrowCollapsed || (!panelOpen && !overviewOnly)) {
      return null;
    }

    const effectiveWidth = overviewOnly ? OVERVIEW_PANEL_WIDTH : clampWorkingPanelWidth(width);
    const tasks = activeSession?.tasks ?? [];

    return (
      <aside
        data-pt-working-sidebar="1"
        {...sx(styles.asideWrap, { width: effectiveWidth })}
      >
        {!overviewOnly && (
          <div onMouseDown={handleDividerMouseDown} {...sx(styles.divider)} />
        )}

        {overviewOnly ? (
          <div style={{ display: 'flex', flex: 1, flexDirection: 'column', overflow: 'hidden' }}>
            <OverviewPane onOpenTab={onChangeTab} onToggleTerminal={onToggleTerminal} />
          </div>
        ) : (
          <div {...sx(styles.panel)}>
            <div {...sx(styles.tabsBar)}>
              <div {...sx(styles.tabsLeft)}>
                <button
                  onClick={() => onChangeTab('overview')}
                  type="button"
                  {...sx(styles.tabChip, activeTab === 'overview' && styles.tabChipActive)}
                >
                  <LayoutGrid size={13} />
                  <span>{language === 'en' ? 'Overview' : '概览'}</span>
                </button>
                <button
                  onClick={() => onChangeTab('file')}
                  type="button"
                  {...sx(styles.tabChip, activeTab === 'file' && styles.tabChipActive)}
                >
                  <Files size={13} />
                  <span>{language === 'en' ? 'Files' : '文件'}</span>
                </button>
                <button
                  onClick={() => onChangeTab('review')}
                  type="button"
                  {...sx(styles.tabChip, activeTab === 'review' && styles.tabChipActive)}
                >
                  <GitPullRequest size={13} />
                  <span>{language === 'en' ? 'Review' : '审查'}</span>
                </button>
                <button
                  onClick={() => onChangeTab('tasks')}
                  type="button"
                  {...sx(styles.tabChip, activeTab === 'tasks' && styles.tabChipActive)}
                >
                  <ClipboardList size={13} />
                  <span>{language === 'en' ? 'Tasks' : '任务'}</span>
                </button>
              </div>
              <ActionIcon
                icon={PanelRightClose}
                onClick={onClose}
                size="small"
                title={language === 'en' ? 'Close Panel' : '收起右侧工作栏'}
              />
            </div>

            {activeTab === 'overview' && (
              <OverviewPane onOpenTab={onChangeTab} onToggleTerminal={onToggleTerminal} />
            )}
            {activeTab === 'file' && <Suspense><FilesPane /></Suspense>}
            {activeTab === 'review' && <Suspense><ReviewPane /></Suspense>}
            {activeTab === 'tasks' && (
              <div {...sx(styles.taskScroll)}>
                <ClaudeTaskList key={sessionId} language={language} sessionId={sessionId} />
                <strong>{language === 'en' ? 'Todos' : '待办'}</strong>
                {tasks.length === 0 ? (
                  <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12.5, padding: 24, textAlign: 'center' }}>
                    {language === 'en' ? 'No todos in this session' : '当前会话没有待办'}
                  </div>
                ) : (
                  tasks.map((task) => (
                    <div key={task.id} {...sx(styles.taskCard)}>
                      {task.status === 'completed' ? (
                        <CheckCircle2 color="#22c55e" size={16} />
                      ) : task.status === 'in_progress' ? (
                        <Loader2 className="pt-spin" color="#1677ff" size={16} />
                      ) : (
                        <Circle color="#9ca3af" size={16} />
                      )}
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 13, fontWeight: 500 }}>
                          #{task.id} {task.subject}
                        </div>
                        {task.description && (
                          <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12, marginTop: 2 }}>
                            {task.description}
                          </div>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        )}
      </aside>
    );
  },
);

WorkingSidebar.displayName = 'WorkingSidebar';
