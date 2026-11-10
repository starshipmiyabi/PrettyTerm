// Upstream: lobehub/lobehub@00167e7b0f014e640194be732dd251931d663874 (src/features/Conversation/WorkingSidebar/layout.ts)

export const OVERVIEW_PANEL_WIDTH = 340;
export const OVERVIEW_GAP = 32;
export const MIN_PANEL_WIDTH = 300;
export const MAX_PANEL_WIDTH = 1200;
export const COLLAPSE_DRAG_THRESHOLD = 320;
export const CANVAS_MIN_WIDTH = 560;
export const AUTO_COLLAPSE_HOST_WIDTH = 960;

export function clampWorkingPanelWidth(width: number): number {
  return Math.min(MAX_PANEL_WIDTH, Math.max(MIN_PANEL_WIDTH, Math.round(width)));
}
