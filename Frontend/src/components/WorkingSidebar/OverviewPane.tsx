import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  ChevronRight,
  ClipboardList,
  Files,
  Folder,
  GitPullRequest,
  Laptop,
  SquareTerminal,
} from 'lucide-react';
import { memo } from 'react';

import type { WorkingTabKind } from '@/bridge/contracts';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  scrollBody: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
    overflowY: 'auto',
    padding: 14,
  },
  card: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 16,
    borderStyle: 'solid',
    borderWidth: 1,
    boxShadow: cssVar.boxShadowTertiary,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  deviceBlock: {
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
    padding: 14,
  },
  deviceRow: {
    alignItems: 'center',
    display: 'flex',
    gap: 10,
  },
  glyphBox: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillQuaternary,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 10,
    borderStyle: 'solid',
    borderWidth: 1,
    color: cssVar.colorText,
    display: 'flex',
    flexShrink: 0,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  primaryTitle: {
    color: cssVar.colorText,
    fontSize: 13.5,
    fontWeight: 600,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  subLine: {
    alignItems: 'center',
    color: cssVar.colorTextTertiary,
    display: 'flex',
    fontSize: 11.5,
    gap: 5,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  metricsGrid: {
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    padding: 14,
  },
  meterRow: {
    alignItems: 'center',
    display: 'flex',
    gap: 8,
    justifyContent: 'space-between',
  },
  meterLabel: {
    color: cssVar.colorTextSecondary,
    flexShrink: 0,
    fontSize: 12,
    width: 72,
  },
  barsWrap: {
    alignItems: 'center',
    display: 'flex',
    flex: 1,
    gap: 2,
  },
  tick: {
    backgroundColor: cssVar.colorFillSecondary,
    borderRadius: 1.5,
    flex: 1,
    height: 11,
  },
  meterVal: {
    fontSize: 12,
    fontWeight: 600,
    minWidth: 36,
    textAlign: 'right',
  },
  costRow: {
    color: cssVar.colorTextSecondary,
    display: 'flex',
    fontSize: 12,
    justifyContent: 'space-between',
    marginTop: 2,
  },
  navList: {
    display: 'flex',
    flexDirection: 'column',
    padding: 6,
  },
  navItem: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 10,
    borderWidth: 0,
    color: cssVar.colorText,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 13,
    gap: 10,
    paddingBlock: 9,
    paddingInline: 10,
    textAlign: 'left',
    width: '100%',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  navBadge: {
    color: cssVar.colorTextTertiary,
    fontSize: 11.5,
    marginLeft: 'auto',
  },
});

function SegmentedMeter({
  label,
  percent,
  subtext,
}: {
  label: string;
  percent: number | null;
  subtext?: string;
}) {
  const pct = percent === null ? 0 : Math.min(100, Math.max(0, percent));
  const totalTicks = 24;
  const activeCount = percent === null ? 0 : Math.round((pct / 100) * totalTicks);
  const color = pct >= 90 ? '#ef4444' : pct >= 75 ? '#d97706' : '#16a34a';

  return (
    <div title={subtext} {...sx(styles.meterRow)}>
      <span {...sx(styles.meterLabel)}>{label}</span>
      <div {...sx(styles.barsWrap)}>
        {Array.from({ length: totalTicks }, (_, idx) => (
          <span
            key={idx}
            {...sx(styles.tick, idx < activeCount && { backgroundColor: color })}
          />
        ))}
      </div>
      <span {...sx(styles.meterVal, { color: percent !== null ? color : 'var(--lobe-color-text-tertiary)' })}>
        {percent === null ? '—' : `${Math.round(pct)}%`}
      </span>
    </div>
  );
}

export interface OverviewPaneProps {
  onOpenTab: (tab: WorkingTabKind) => void;
  onToggleTerminal: () => void;
}

export const OverviewPane = memo<OverviewPaneProps>(({ onOpenTab, onToggleTerminal }) => {
  const activeSession = usePTSlice('activeSession');
  const activeTab = usePTSlice('activeTab');
  const language = usePTSlice('language');
  const usage = usePTSlice('usage');
  const windowState = usePTSlice('windowState');
  const cwd = activeSession?.cwd || windowState.defaultCwd || '~';
  const dirName = cwd.split('/').filter(Boolean).pop() || cwd;
  const isConnected = Boolean(activeTab?.running || activeSession?.connected);
  const hostName = windowState.hostName || 'MacBook';

  const ctxPct =
    activeSession && (activeSession.contextWindow ?? 0) > 0 && (activeSession.contextUsed ?? 0) > 0
      ? ((activeSession.contextUsed ?? 0) / (activeSession.contextWindow ?? 200000)) * 100
      : null;

  const fivePct = usage?.available ? usage.fiveHourPercent : null;
  const sevenPct = usage?.available ? usage.sevenDayPercent : null;

  return (
    <div data-pt-overview-pane="1" {...sx(styles.scrollBody)}>
      <div {...sx(styles.card)}>
        <div {...sx(styles.deviceBlock)}>
          <div {...sx(styles.deviceRow)}>
            <div {...sx(styles.glyphBox)}>
              <Folder size={17} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div {...sx(styles.primaryTitle)}>{dirName}</div>
              <div {...sx(styles.subLine)} title={cwd}>
                <span style={{ backgroundColor: '#1677ff', borderRadius: 99, height: 6, width: 6 }} />
                <span>{cwd}</span>
              </div>
            </div>
          </div>

          <div {...sx(styles.deviceRow)}>
            <div {...sx(styles.glyphBox)}>
              <Laptop size={17} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div {...sx(styles.primaryTitle)}>{hostName}</div>
              <div {...sx(styles.subLine)}>
                <span
                  style={{
                    backgroundColor: isConnected ? '#22c55e' : '#9ca3af',
                    borderRadius: 99,
                    height: 6,
                    width: 6,
                  }}
                />
                <span>
                  {isConnected
                    ? language === 'en'
                      ? 'Claude Synced · Running'
                      : '在线 · Claude 已同步'
                    : language === 'en'
                      ? 'Idle · Ready to connect'
                      : '待命 · 可点击连接'}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div {...sx(styles.metricsGrid)}>
          <SegmentedMeter
            label={language === 'en' ? 'Context' : '上下文使用'}
            percent={ctxPct}
            subtext={
              activeSession?.contextUsed
                ? `${activeSession.contextUsed.toLocaleString()} / ${(activeSession.contextWindow ?? 200000).toLocaleString()}`
                : undefined
            }
          />
          <SegmentedMeter
            label={language === 'en' ? '5h Quota' : '5 小时额度'}
            percent={fivePct}
            subtext={usage?.fiveHourResetText}
          />
          <SegmentedMeter
            label={language === 'en' ? '7d Quota' : '7 天额度'}
            percent={sevenPct}
            subtext={usage?.sevenDayResetText}
          />

          <div {...sx(styles.costRow)}>
            <span>{language === 'en' ? 'API Est. Cost' : 'API 等价成本'}</span>
            <span style={{ color: 'var(--lobe-color-text)', fontWeight: 600 }}>
              {activeSession?.apiCostAvailable
                ? `$${(activeSession.apiEquivalentCostUSD ?? 0).toFixed(3)}`
                : '—'}
              {(activeSession?.codeLinesAdded || activeSession?.codeLinesRemoved) ? (
                <span style={{ fontSize: 11, marginLeft: 6 }}>
                  <span style={{ color: '#22c55e' }}>+{activeSession.codeLinesAdded ?? 0}</span>{' '}
                  <span style={{ color: '#ef4444' }}>-{activeSession.codeLinesRemoved ?? 0}</span>
                </span>
              ) : null}
            </span>
          </div>
        </div>

        <div {...sx(styles.navList)}>
          <button onClick={() => onOpenTab('file')} type="button" {...sx(styles.navItem)}>
            <Files size={15} />
            <span>{language === 'en' ? 'Files' : '文件'}</span>
            <span {...sx(styles.navBadge)}>
              <ChevronRight size={14} />
            </span>
          </button>

          <button onClick={() => onOpenTab('review')} type="button" {...sx(styles.navItem)}>
            <GitPullRequest size={15} />
            <span>{language === 'en' ? 'Git Review' : '改动审查'}</span>
            {(activeSession?.changedFiles?.length ?? 0) > 0 && (
              <span style={{ color: '#1677ff', fontSize: 11.5, marginLeft: 4 }}>
                {activeSession!.changedFiles!.length}
              </span>
            )}
            <span {...sx(styles.navBadge)}>
              <ChevronRight size={14} />
            </span>
          </button>

          <button onClick={() => onOpenTab('tasks')} type="button" {...sx(styles.navItem)}>
            <ClipboardList size={15} />
            <span>{language === 'en' ? 'Tasks' : '任务'}</span>
            {(activeSession?.tasks?.length ?? 0) > 0 && (
              <span style={{ fontSize: 11.5, marginLeft: 4 }}>
                {activeSession!.tasks!.length}
              </span>
            )}
            <span {...sx(styles.navBadge)}>
              <ChevronRight size={14} />
            </span>
          </button>

          <button onClick={onToggleTerminal} type="button" {...sx(styles.navItem)}>
            <SquareTerminal size={15} />
            <span>{language === 'en' ? 'Terminal' : '终端'}</span>
            <span {...sx(styles.navBadge)}>
              <ChevronRight size={14} />
            </span>
          </button>
        </div>
      </div>
    </div>
  );
});

OverviewPane.displayName = 'OverviewPane';
