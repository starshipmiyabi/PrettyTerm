import Claude from '@lobehub/icons/es/Claude';
import { ActionIcon, Button, Tag } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { X } from 'lucide-react';
import { memo, useCallback, useEffect, useRef, useState } from 'react';

import type { WorkingTabKind } from '@/bridge/contracts';
import { invokeNativeUI, triggerWindowDrag } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { AgentSidebar } from '@/components/AgentSidebar/AgentSidebar';
import { ChatHeader } from '@/components/Conversation/ChatHeader';
import { ChatInput } from '@/components/Conversation/ChatInput';
import { ChatList } from '@/components/Conversation/ChatList';
import { NewChatModal } from '@/components/Modals/NewChatModal';
import { RenameModal } from '@/components/Modals/RenameModal';
import { TitleBar } from '@/components/TitleBar/TitleBar';
import { TerminalDrawer } from '@/components/WorkingSidebar/TerminalDrawer';
import { WorkingSidebar } from '@/components/WorkingSidebar/WorkingSidebar';
import { DesktopLayoutContainer } from '@/upstream/layout/DesktopLayoutContainer';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  shell: {
    backgroundColor: cssVar.colorBgLayout,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    minHeight: 0,
    overflow: 'hidden',
    width: '100%',
  },
  bodyRow: {
    display: 'flex',
    flex: 1,
    minHeight: 0,
    minWidth: 0,
    overflow: 'hidden',
    width: '100%',
  },
  canvasRow: {
    display: 'flex',
    flex: 1,
    minHeight: 0,
    minWidth: 0,
    overflow: 'hidden',
    width: '100%',
  },
  centerColumn: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minHeight: 0,
    minWidth: 0,
    overflow: 'hidden',
  },
  floatingShell: {
    backgroundColor: cssVar.colorBgContainer,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    minHeight: 0,
    overflow: 'hidden',
    width: '100%',
  },
  floatingHeader: {
    alignItems: 'center',
    backgroundColor: cssVar.colorBgLayout,
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexShrink: 0,
    gap: 8,
    height: 40,
    justifyContent: 'space-between',
    paddingLeft: 14,
    paddingRight: 10,
    userSelect: 'none',
  },
});

const FloatingWorkspace = memo(() => {
  const activeSession = usePTSlice('activeSession');
  const language = usePTSlice('language');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const transcript = usePTSlice('transcript');
  const title = activeSession?.title || transcript.title || 'PrettyTerm';

  const openFile = useCallback((path: string) => {
    void invokeNativeUI('openTranscriptFile', { filePath: path, sessionId: selectedSessionId });
  }, [selectedSessionId]);
  const reviewTurn = useCallback((turnIndex: number) => {
    void invokeNativeUI('openTranscriptEditReview', { sessionId: selectedSessionId, turnIndex });
  }, [selectedSessionId]);

  return (
    <div data-pt-floating-root="1" data-pt-surface="floating" {...sx(styles.floatingShell)}>
      <header
        onMouseDown={(e) => {
          if (e.button === 0 && !(e.target as HTMLElement)?.closest('button')) {
            triggerWindowDrag('floating');
          }
        }}
        {...sx(styles.floatingHeader)}
      >
        <div style={{ alignItems: 'center', display: 'flex', flex: 1, gap: 8, minWidth: 0 }}>
          <Claude.Color size={16} />
          <span
            style={{
              fontSize: 13,
              fontWeight: 600,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {title}
          </span>
          {activeSession?.connected && <Tag color="success">{language === 'en' ? 'Live' : '在线'}</Tag>}
        </div>

        <div style={{ alignItems: 'center', display: 'flex', gap: 4 }}>
          {selectedSessionId && !activeSession?.connected && (
            <Button
              onClick={() => void invokeNativeUI('connectClaude', { sessionId: selectedSessionId })}
              size="small"
              type="primary"
            >
              {language === 'en' ? 'Connect' : '连接'}
            </Button>
          )}
          <ActionIcon
            icon={X}
            onClick={() => void invokeNativeUI('toggleFloatingWindow', { sessionId: selectedSessionId })}
            size="small"
          />
        </div>
      </header>

      <ChatList onOpenFile={openFile} onReviewTurn={reviewTurn} />

      <ChatInput compact surface="floating" />
    </div>
  );
});

FloatingWorkspace.displayName = 'FloatingWorkspace';

export const App = memo(() => {
  const activeTab = usePTSlice('activeTab');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const setSidebarCollapsed = usePTSlice('setSidebarCollapsed');
  const setTerminalOpen = usePTSlice('setTerminalOpen');
  const sidebarCollapsed = usePTSlice('sidebarCollapsed');
  const terminalOpen = usePTSlice('terminalOpen');
  const windowState = usePTSlice('windowState');
  const workspace = usePTSlice('workspace');

  const surface = windowState.surface ?? 'main';
  const [newChatOpen, setNewChatOpen] = useState(false);

  // Navigation history stack (back/forward across selected sessions)
  const [navHistory, setNavHistory] = useState<string[]>([]);
  const [navCursor, setNavCursor] = useState(-1);
  const jumpingRef = useRef(false);

  useEffect(() => {
    if (!selectedSessionId) return;
    if (jumpingRef.current) {
      jumpingRef.current = false;
      return;
    }
    setNavHistory((prev) => {
      if (prev[navCursor] === selectedSessionId) return prev;
      const sliced = prev.slice(0, navCursor + 1);
      const next = [...sliced, selectedSessionId];
      setNavCursor(next.length - 1);
      return next;
    });
  }, [navCursor, selectedSessionId]);

  const handleGoBack = useCallback(() => {
    if (navCursor <= 0) return;
    const nextIdx = navCursor - 1;
    jumpingRef.current = true;
    setNavCursor(nextIdx);
    void invokeNativeUI('selectSession', { sessionId: navHistory[nextIdx] });
  }, [navCursor, navHistory]);

  const handleGoForward = useCallback(() => {
    if (navCursor >= navHistory.length - 1) return;
    const nextIdx = navCursor + 1;
    jumpingRef.current = true;
    setNavCursor(nextIdx);
    void invokeNativeUI('selectSession', { sessionId: navHistory[nextIdx] });
  }, [navCursor, navHistory]);

  // Right WorkingSidebar preferences synced cleanly with active workspace tab
  const [panelWidth, setPanelWidth] = useState(360);
  const [localPanelOpen, setLocalPanelOpen] = useState(false);
  const [localOverviewOpen, setLocalOverviewOpen] = useState(true);
  const [localWorkingTab, setLocalWorkingTab] = useState<WorkingTabKind>('overview');

  useEffect(() => {
    if (!activeTab) return;
    setLocalPanelOpen(Boolean(activeTab.panelExpanded));
    setLocalOverviewOpen(activeTab.overviewExpanded !== false);
    if (activeTab.activeToolPageKind) {
      setLocalWorkingTab(activeTab.activeToolPageKind);
    } else if (activeTab.reviewToolPageOpen) {
      setLocalWorkingTab('review');
    } else if (activeTab.fileToolPageOpen) {
      setLocalWorkingTab('file');
    } else {
      setLocalWorkingTab('overview');
    }
  }, [activeTab]);

  const persistPanelPrefs = useCallback(
    (next: {
      activeToolPageKind?: WorkingTabKind;
      overviewExpanded?: boolean;
      panelExpanded?: boolean;
    }) => {
      if (!activeTab) return;
      void invokeNativeUI('savePanelState', {
        activeToolPageKind: next.activeToolPageKind ?? localWorkingTab,
        overviewExpanded: next.overviewExpanded ?? localOverviewOpen,
        panelExpanded: next.panelExpanded ?? localPanelOpen,
        tabId: activeTab.id,
      });
    },
    [activeTab, localOverviewOpen, localPanelOpen, localWorkingTab],
  );

  const openWorkingTab = useCallback(
    (tab: WorkingTabKind) => {
      setLocalWorkingTab(tab);
      setLocalPanelOpen(true);
      persistPanelPrefs({ activeToolPageKind: tab, panelExpanded: true });
      if (tab === 'review') {
        void invokeNativeUI('refreshGitReview', { mode: 'git' });
      }
    },
    [persistPanelPrefs],
  );

  const toggleOverview = useCallback(() => {
    if (localPanelOpen) {
      setLocalPanelOpen(false);
      setLocalOverviewOpen(true);
      persistPanelPrefs({ overviewExpanded: true, panelExpanded: false });
    } else {
      const next = !localOverviewOpen;
      setLocalOverviewOpen(next);
      persistPanelPrefs({ overviewExpanded: next, panelExpanded: false });
    }
  }, [localOverviewOpen, localPanelOpen, persistPanelPrefs]);

  const togglePanel = useCallback(() => {
    const next = !localPanelOpen;
    setLocalPanelOpen(next);
    if (next && localWorkingTab === 'overview') {
      setLocalWorkingTab('file');
      persistPanelPrefs({ activeToolPageKind: 'file', panelExpanded: next });
    } else {
      persistPanelPrefs({ panelExpanded: next });
    }
  }, [localPanelOpen, localWorkingTab, persistPanelPrefs]);

  const openTranscriptFile = useCallback((filePath: string) => {
    void invokeNativeUI('openTranscriptFile', { filePath, sessionId: selectedSessionId, tabId: activeTab?.id });
  }, [activeTab?.id, selectedSessionId]);

  const reviewTranscriptTurn = useCallback((turnIndex: number) => {
    void invokeNativeUI('openTranscriptEditReview', { sessionId: selectedSessionId, turnIndex });
  }, [selectedSessionId]);

  // Desktop keyboard shortcuts
  useEffect(() => {
    if (surface !== 'main') return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      if (e.key.toLowerCase() === 'b' && !e.shiftKey) {
        e.preventDefault();
        setSidebarCollapsed((v) => !v);
      } else if (e.key.toLowerCase() === 't' && !e.shiftKey) {
        e.preventDefault();
        void invokeNativeUI('newTab', {});
      } else if (e.key.toLowerCase() === 'w' && !e.shiftKey && workspace.tabs.length > 1 && activeTab) {
        e.preventDefault();
        void invokeNativeUI('closeTab', { tabId: activeTab.id });
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [activeTab, setSidebarCollapsed, surface, workspace.tabs.length]);

  if (surface === 'floating') {
    return <FloatingWorkspace />;
  }

  const overviewOnly = !localPanelOpen && localOverviewOpen;

  return (
    <div data-pt-main-shell="1" data-pt-surface="main" {...sx(styles.shell)}>
      <TitleBar
        canGoBack={navCursor > 0}
        canGoForward={navCursor >= 0 && navCursor < navHistory.length - 1}
        onGoBack={handleGoBack}
        onGoForward={handleGoForward}
      />

      <div {...sx(styles.bodyRow)}>
        <AgentSidebar
          onOpenNewChat={() => setNewChatOpen(true)}
          onOpenWorkingTab={openWorkingTab}
        />

        <DesktopLayoutContainer sidebarExpanded={!sidebarCollapsed}>
          <div {...sx(styles.canvasRow)}>
            <div {...sx(styles.centerColumn)}>
              <ChatHeader
                onSelectWorkingTab={openWorkingTab}
                onToggleOverview={toggleOverview}
                onTogglePanel={togglePanel}
                overviewActive={localOverviewOpen}
                panelOpen={localPanelOpen}
                panelTab={localWorkingTab}
              />

              <ChatList onOpenFile={openTranscriptFile} onReviewTurn={reviewTranscriptTurn} />

              <ChatInput
                onOpenGitDir={() => openWorkingTab('review')}
                surface="main"
              />

              {terminalOpen && <TerminalDrawer onClose={() => setTerminalOpen(false)} />}
            </div>

            <WorkingSidebar
              activeTab={localWorkingTab}
              onChangeTab={openWorkingTab}
              onClose={() => {
                setLocalPanelOpen(false);
                setLocalOverviewOpen(false);
                persistPanelPrefs({ overviewExpanded: false, panelExpanded: false });
              }}
              onToggleTerminal={() => setTerminalOpen((v) => !v)}
              onWidthChange={setPanelWidth}
              overviewOnly={overviewOnly}
              panelOpen={localPanelOpen}
              width={panelWidth}
            />
          </div>
        </DesktopLayoutContainer>
      </div>

      <RenameModal />
      <NewChatModal onClose={() => setNewChatOpen(false)} open={newChatOpen} />
    </div>
  );
});

App.displayName = 'App';
