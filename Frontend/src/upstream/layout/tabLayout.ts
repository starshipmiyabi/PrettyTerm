// Upstream: lobehub/lobehub@00167e7b0f014e640194be732dd251931d663874 (src/features/Electron/titlebar/TabBar/tabLayout.ts)

export const MAX_TAB_WIDTH = 200;
export const MIN_TAB_WIDTH = 40;
export const ACTIVE_TAB_MIN_WIDTH = 150;
export const TAB_ICON_SIZE = 16;
export const TAB_INLINE_INSET = 8;
export const TAB_GAP = 2;
export const OVERFLOW_CONTROL_WIDTH = 34;

export type TabTier = 'compact' | 'full' | 'icon' | 'narrow';

export interface TabPlacement {
  id: string;
  index: number;
  width: number;
  x: number;
  tier: TabTier;
}

export interface TabLayoutResult {
  hiddenIndices: number[];
  placements: TabPlacement[];
  total: number;
  visibleIndices: number[];
}

export const resolveTabTier = (width: number): TabTier => {
  if (width >= 130) return 'full';
  if (width >= 96) return 'compact';
  if (width >= 60) return 'icon';
  return 'narrow';
};

export function layoutStrip({
  activeId,
  stripWidth,
  tabIds,
}: {
  activeId: string;
  stripWidth: number;
  tabIds: string[];
}): TabLayoutResult {
  const count = tabIds.length;
  if (count === 0) {
    return { hiddenIndices: [], placements: [], total: 0, visibleIndices: [] };
  }

  const usable = Math.max(0, stripWidth - OVERFLOW_CONTROL_WIDTH);
  const activeIdx = Math.max(0, tabIds.indexOf(activeId));

  // Try fitting all tabs first
  const totalGapAll = Math.max(0, count - 1) * TAB_GAP;
  const maxAllowedByMin = Math.floor((usable + TAB_GAP) / (MIN_TAB_WIDTH + TAB_GAP));
  const visibleCount = Math.max(1, Math.min(count, maxAllowedByMin || count));

  let visibleIndices: number[] = [];
  if (visibleCount >= count) {
    visibleIndices = tabIds.map((_, i) => i);
  } else {
    // Keep active tab centered inside visible window
    const half = Math.floor(visibleCount / 2);
    let start = Math.max(0, activeIdx - half);
    if (start + visibleCount > count) {
      start = Math.max(0, count - visibleCount);
    }
    for (let i = start; i < Math.min(count, start + visibleCount); i++) {
      visibleIndices.push(i);
    }
    if (!visibleIndices.includes(activeIdx)) {
      visibleIndices[visibleIndices.length - 1] = activeIdx;
    }
  }

  const hiddenSet = new Set(tabIds.map((_, i) => i).filter((i) => !visibleIndices.includes(i)));
  const hiddenIndices = Array.from(hiddenSet);
  const needsOverflow = hiddenIndices.length > 0;
  const availableForTabs = Math.max(
    MIN_TAB_WIDTH,
    usable - (needsOverflow ? OVERFLOW_CONTROL_WIDTH : 0) - Math.max(0, visibleIndices.length - 1) * TAB_GAP,
  );

  const n = visibleIndices.length;
  const widths = new Array<number>(n);

  if (n === 1) {
    widths[0] = Math.max(ACTIVE_TAB_MIN_WIDTH, Math.min(MAX_TAB_WIDTH, availableForTabs));
  } else {
    const activePos = visibleIndices.indexOf(activeIdx);
    const activeMin = activePos >= 0 ? Math.min(ACTIVE_TAB_MIN_WIDTH, availableForTabs - (n - 1) * MIN_TAB_WIDTH) : 0;
    const equal = availableForTabs / n;
    if (equal >= ACTIVE_TAB_MIN_WIDTH || activePos < 0) {
      const clamped = Math.max(MIN_TAB_WIDTH, Math.min(MAX_TAB_WIDTH, equal));
      widths.fill(clamped);
    } else {
      const activeWidth = Math.min(MAX_TAB_WIDTH, Math.max(MIN_TAB_WIDTH, activeMin));
      const otherWidth = Math.max(
        MIN_TAB_WIDTH,
        Math.min(MAX_TAB_WIDTH, (availableForTabs - activeWidth) / (n - 1)),
      );
      for (let i = 0; i < n; i++) {
        widths[i] = i === activePos ? activeWidth : otherWidth;
      }
    }
  }

  const placements: TabPlacement[] = [];
  let cursor = 0;
  for (let i = 0; i < n; i++) {
    const origIndex = visibleIndices[i];
    const width = Math.round(widths[i]);
    placements.push({
      id: tabIds[origIndex],
      index: origIndex,
      tier: resolveTabTier(width),
      width,
      x: cursor,
    });
    cursor += width + (i < n - 1 ? TAB_GAP : 0);
  }

  return {
    hiddenIndices,
    placements,
    total: needsOverflow ? cursor : Math.min(cursor + (totalGapAll >= 0 ? 0 : 0), cursor),
    visibleIndices,
  };
}
