import Claude from '@lobehub/icons/es/Claude';
import { ActionIcon, DropdownMenu, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { ChevronDown, Plus, X } from 'lucide-react';
import { AnimatePresence } from 'motion/react';
import * as m from 'motion/react-m';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { WorkspaceTabItem } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { layoutStrip, MAX_TAB_WIDTH, MIN_TAB_WIDTH } from '@/upstream/layout/tabLayout';
import { TAB_SPRING } from '@/upstream/layout/tabMotion';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  stripWrap: {
    alignItems: 'center',
    display: 'flex',
    flex: 1,
    gap: 2,
    height: 36,
    minWidth: 0,
    overflow: 'hidden',
    position: 'relative',
  },
  track: {
    alignItems: 'center',
    display: 'flex',
    gap: 2,
    height: 32,
    minWidth: 0,
    position: 'relative',
  },
  tab: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderColor: 'transparent',
    borderRadius: 8,
    borderStyle: 'solid',
    borderWidth: 1,
    boxSizing: 'border-box',
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'flex',
    flexShrink: 0,
    fontSize: 12.5,
    gap: 6,
    height: 30,
    overflow: 'hidden',
    paddingInline: 8,
    position: 'relative',
    transition: 'background-color 0.14s ease, color 0.14s ease, border-color 0.14s ease',
    userSelect: 'none',
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
      color: cssVar.colorText,
    },
  },
  tabActive: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorBorderSecondary,
    boxShadow: cssVar.boxShadowTertiary,
    color: cssVar.colorText,
    fontWeight: 500,
    ':hover': {
      backgroundColor: cssVar.colorBgContainer,
    },
  },
  iconSlot: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    position: 'relative',
  },
  dot: {
    backgroundColor: cssVar.colorSuccess,
    borderRadius: 99,
    bottom: -1,
    boxShadow: `0 0 0 1.5px ${cssVar.colorBgContainer}`,
    height: 6,
    position: 'absolute',
    right: -1,
    width: 6,
  },
  label: {
    flex: 1,
    minWidth: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  closeBtn: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 5,
    borderWidth: 0,
    color: cssVar.colorTextTertiary,
    cursor: 'pointer',
    display: 'flex',
    flexShrink: 0,
    height: 18,
    justifyContent: 'center',
    opacity: 0.72,
    padding: 0,
    width: 18,
    ':hover': {
      backgroundColor: cssVar.colorFillSecondary,
      color: cssVar.colorText,
      opacity: 1,
    },
  },
  addBtn: {
    flexShrink: 0,
  },
});

export const TabBar = memo(() => {
  const language = usePTSlice('language');
  const workspace = usePTSlice('workspace');
  const tabs = workspace.tabs;
  const activeTabId = workspace.activeTabId;

  const stripRef = useRef<HTMLDivElement>(null);
  const [stripWidth, setStripWidth] = useState(560);
  const [dragTabId, setDragTabId] = useState<string | null>(null);
  const [dragTargetIndex, setDragTargetIndex] = useState<number | null>(null);

  useEffect(() => {
    const el = stripRef.current;
    if (!el) return;
    const measure = () => setStripWidth(Math.max(160, el.clientWidth - 40));
    measure();
    if (typeof ResizeObserver !== 'undefined') {
      const ro = new ResizeObserver(measure);
      ro.observe(el);
      return () => ro.disconnect();
    }
    window.addEventListener('resize', measure);
    return () => window.removeEventListener('resize', measure);
  }, []);

  const orderedTabs = useMemo(() => {
    if (!dragTabId || dragTargetIndex === null) return tabs;
    const fromIdx = tabs.findIndex((t) => t.id === dragTabId);
    if (fromIdx < 0 || fromIdx === dragTargetIndex) return tabs;
    const next = tabs.slice();
    const [moved] = next.splice(fromIdx, 1);
    next.splice(dragTargetIndex, 0, moved);
    return next;
  }, [dragTabId, dragTargetIndex, tabs]);

  const tabIds = useMemo(() => orderedTabs.map((t) => t.id), [orderedTabs]);
  const layout = useMemo(
    () => layoutStrip({ activeId: activeTabId, stripWidth, tabIds }),
    [activeTabId, stripWidth, tabIds],
  );

  const placementById = useMemo(
    () => new Map(layout.placements.map((p) => [p.id, p])),
    [layout.placements],
  );

  const hiddenItems = useMemo<DropdownItem[]>(() => {
    return layout.hiddenIndices.map((idx) => {
      const tab = orderedTabs[idx];
      return {
        key: tab.id,
        label: tab.title || (language === 'en' ? 'New Tab' : '新标签'),
        onClick: () => {
          void invokeNativeUI('selectTab', { tabId: tab.id });
        },
      };
    });
  }, [language, layout.hiddenIndices, orderedTabs]);

  const handleSelect = useCallback((tabId: string) => {
    void invokeNativeUI('selectTab', { tabId });
  }, []);

  const handleClose = useCallback((e: React.MouseEvent, tabId: string) => {
    e.stopPropagation();
    void invokeNativeUI('closeTab', { tabId });
  }, []);

  const handleNewTab = useCallback(() => {
    void invokeNativeUI('newTab', {});
  }, []);

  const commitReorder = useCallback(
    (finalList: WorkspaceTabItem[]) => {
      const ids = finalList.map((t) => t.id);
      const originalIds = tabs.map((t) => t.id);
      if (ids.join('|') !== originalIds.join('|')) {
        void invokeNativeUI('reorderTabs', { tabIds: ids });
      }
    },
    [tabs],
  );

  return (
    <div data-pt-tabbar="1" ref={stripRef} {...sx(styles.stripWrap)}>
      <div {...sx(styles.track)}>
        <AnimatePresence initial={false}>
          {layout.visibleIndices.map((idx) => {
            const tab = orderedTabs[idx];
            if (!tab) return null;
            const placement = placementById.get(tab.id);
            const width = placement?.width ?? MAX_TAB_WIDTH;
            const tier = placement?.tier ?? 'full';
            const isActive = tab.id === activeTabId;
            const label = tab.title || (language === 'en' ? 'New Tab' : '新标签');
            const showClose = tabs.length > 1 && (isActive || width >= 96);

            return (
              <m.div
                key={tab.id}
                layout
                data-pt-tab-id={tab.id}
                data-tab-item="1"
                draggable={tabs.length > 1}
                initial={{ opacity: 0, width: MIN_TAB_WIDTH }}
                animate={{ opacity: 1, width }}
                exit={{ opacity: 0, width: 0 }}
                transition={TAB_SPRING}
                title={label}
                onClick={() => handleSelect(tab.id)}
                onDragStart={() => {
                  setDragTabId(tab.id);
                  setDragTargetIndex(idx);
                }}
                onDragOver={(e) => {
                  e.preventDefault();
                  if (dragTabId && dragTargetIndex !== idx) {
                    setDragTargetIndex(idx);
                  }
                }}
                onDragEnd={() => {
                  const snapshot = orderedTabs;
                  setDragTabId(null);
                  setDragTargetIndex(null);
                  commitReorder(snapshot);
                }}
                onAuxClick={(e) => {
                  if (e.button === 1 && tabs.length > 1) handleClose(e, tab.id);
                }}
                {...sx(styles.tab, isActive && styles.tabActive)}
              >
                <span {...sx(styles.iconSlot)}>
                  <Claude.Color size={15} />
                  {(tab.running || tab.responding) && <span {...sx(styles.dot)} />}
                </span>
                {tier !== 'narrow' && tier !== 'icon' && (
                  <span {...sx(styles.label)}>{label}</span>
                )}
                {showClose && (
                  <button
                    aria-label={language === 'en' ? 'Close tab' : '关闭标签'}
                    onClick={(e) => handleClose(e, tab.id)}
                    type="button"
                    {...sx(styles.closeBtn)}
                  >
                    <X size={12} />
                  </button>
                )}
              </m.div>
            );
          })}
        </AnimatePresence>

        {hiddenItems.length > 0 && (
          <DropdownMenu items={hiddenItems}>
            <ActionIcon
              icon={ChevronDown}
              size="small"
              title={language === 'en' ? 'Hidden tabs' : '更多标签页'}
            />
          </DropdownMenu>
        )}

        <ActionIcon
          data-pt-new-tab-btn="1"
          icon={Plus}
          onClick={handleNewTab}
          size="small"
          title={language === 'en' ? 'New Tab (⌘T)' : '新建标签页 (⌘T)'}
          {...sx(styles.addBtn)}
        />
      </div>
    </div>
  );
});

TabBar.displayName = 'TabBar';
