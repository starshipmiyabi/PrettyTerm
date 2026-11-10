import { DropdownMenu, type DropdownItem } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { ChevronDown, Folder, Infinity as InfinityIcon, Laptop } from 'lucide-react';
import { memo, useMemo, useState } from 'react';

import type { SessionSummary, UILanguage } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  bar: {
    alignItems: 'center',
    color: cssVar.colorTextTertiary,
    display: 'flex',
    fontSize: 12,
    gap: 8,
    justifyContent: 'space-between',
    marginTop: 8,
    paddingInline: 6,
    position: 'relative',
    userSelect: 'none',
  },
  left: {
    alignItems: 'center',
    display: 'flex',
    flex: 1,
    gap: 10,
    minWidth: 0,
    overflow: 'hidden',
  },
  right: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: 10,
    position: 'relative',
  },
  chipBtn: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: 6,
    borderWidth: 0,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'inline-flex',
    fontSize: 12,
    gap: 4,
    maxWidth: 190,
    paddingBlock: 2,
    paddingInline: 5,
    whiteSpace: 'nowrap',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
      color: cssVar.colorText,
    },
  },
  dot: {
    backgroundColor: cssVar.colorTextTertiary,
    borderRadius: 99,
    height: 6,
    width: 6,
  },
  dotConnected: {
    backgroundColor: cssVar.colorSuccess,
  },
  ctxPopover: {
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    bottom: 30,
    boxShadow: cssVar.boxShadowSecondary,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    maxHeight: 'min(60vh, 480px)',
    maxWidth: 'calc(100vw - 24px)',
    overflowY: 'auto',
    padding: 12,
    position: 'absolute',
    right: 0,
    width: 360,
    zIndex: 45,
  },
  ctxRow: {
    display: 'flex',
    fontSize: 12,
    gap: 8,
    justifyContent: 'space-between',
  },
  modelLabel: {
    color: cssVar.colorText,
    minWidth: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  usageTable: {
    borderCollapse: 'collapse',
    color: cssVar.colorTextSecondary,
    fontSize: 12,
    width: '100%',
  },
  usageLabel: {
    fontWeight: 400,
    paddingBlock: 3,
    textAlign: 'start',
  },
  usageValue: {
    fontVariantNumeric: 'tabular-nums',
    paddingInlineStart: 10,
    textAlign: 'end',
    whiteSpace: 'nowrap',
  },
  modelSubtotal: {
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    color: cssVar.colorText,
    fontWeight: 600,
    paddingBlock: 5,
  },
});

const usdFormat = new Intl.NumberFormat('en-US', {
  currency: 'USD',
  maximumFractionDigits: 6,
  minimumFractionDigits: 4,
  style: 'currency',
});

const formatCost = (cost?: number) => cost === undefined ? '—' : usdFormat.format(cost);

const formatTokens = (tokens: number) =>
  `${(tokens / 1000).toLocaleString(undefined, { maximumFractionDigits: tokens < 1000 ? 3 : 2 })}K`;

const usageCategories = [
  { cost: 'inputCost', tokens: 'input', en: 'Input', zh: '输入' },
  { cost: 'outputCost', tokens: 'output', en: 'Output', zh: '输出' },
  { cost: 'cacheReadCost', tokens: 'cacheRead', en: 'Cache read', zh: '缓存读取' },
  { cost: 'cacheWriteCost', tokens: 'cacheWrite', en: 'Cache write', zh: '缓存写入' },
] as const;

function ModelUsageTable({ breakdown, language }: {
  breakdown: NonNullable<SessionSummary['modelUsageBreakdown']>;
  language: UILanguage;
}) {
  const models = Object.entries(breakdown).sort(([a, usageA], [b, usageB]) =>
    (usageB.cost ?? -1) - (usageA.cost ?? -1) || a.localeCompare(b),
  );
  if (!models.length) return null;

  return (
    <table {...sx(styles.usageTable)}>
      <thead>
        <tr>
          <th scope="col" {...sx(styles.usageLabel)}>{language === 'en' ? 'Model / Usage' : '模型 / 用量'}</th>
          <th scope="col" {...sx(styles.usageValue)}>Tokens</th>
          <th scope="col" {...sx(styles.usageValue)}>USD</th>
        </tr>
      </thead>
      {models.map(([model, usage]) => (
        <tbody key={model}>
          <tr>
            <th colSpan={2} scope="rowgroup" {...sx(styles.usageLabel, styles.modelSubtotal)}>
              {model === 'unknown' ? (language === 'en' ? 'Unknown model' : '未知模型') : model}
            </th>
            <td {...sx(styles.usageValue, styles.modelSubtotal)}>{formatCost(usage.cost)}</td>
          </tr>
          {usageCategories.map((category) => (
            <tr key={category.tokens}>
              <th scope="row" {...sx(styles.usageLabel)}>{language === 'en' ? category.en : category.zh}</th>
              <td title={usage[category.tokens].toLocaleString()} {...sx(styles.usageValue)}>
                {formatTokens(usage[category.tokens])}
              </td>
              <td {...sx(styles.usageValue)}>{formatCost(usage[category.cost])}</td>
            </tr>
          ))}
        </tbody>
      ))}
    </table>
  );
}

const MODES = [
  { id: 'bypass', label: 'Bypass', wire: 'bypassPermissions' },
  { id: 'auto', label: 'Auto', wire: 'auto' },
  { id: 'acceptEdits', label: 'Accept Edits', wire: 'acceptEdits' },
  { id: 'plan', label: 'Plan', wire: 'plan' },
  { id: 'default', label: 'Default', wire: 'default' },
];

export const ControlBar = memo<{ onOpenGitDir?: () => void }>(({ onOpenGitDir }) => {
  const activeSession = usePTSlice('activeSession');
  const activeTab = usePTSlice('activeTab');
  const language = usePTSlice('language');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const claudeSettings = usePTSlice('claudeSettings');
  const usage = usePTSlice('usage');
  const status = usePTSlice('status');
  const [ctxPopoverOpen, setCtxPopoverOpen] = useState(false);

  const isConnected = Boolean(activeTab?.running || activeSession?.connected);
  const currentMode = claudeSettings?.selectedPermissionMode || 'bypassPermissions';
  const modeLabel = MODES.find((m) => m.wire === currentMode)?.label || currentMode;

  const cwd = activeSession?.cwd || activeTab?.cwd || '';
  const cwdName = cwd ? cwd.split('/').filter(Boolean).pop() || cwd : language === 'en' ? 'No Folder' : '未选择目录';

  const contextUsed = activeSession?.contextUsed ?? 0;
  const contextWindow = activeSession?.contextWindow ?? 200000;
  const modelBreakdown = activeSession?.modelUsageBreakdown;
  const currentModel = claudeSettings?.sessionId === selectedSessionId ? claudeSettings?.selectedModel : undefined;
  const shownModel = currentModel || activeSession?.model;
  const hasUnpricedModels = modelBreakdown && Object.values(modelBreakdown).some((item) => item.cost === undefined);
  const ratio = contextWindow > 0 ? Math.min(1, contextUsed / contextWindow) : 0;
  const ctxPctText = contextUsed > 0 ? `${Math.round(ratio * 100)}%` : '—';

  const fivePct = usage?.available ? usage.fiveHourPercent : null;
  const sevenPct = usage?.available ? usage.sevenDayPercent : null;
  const maxQuota = Math.max(fivePct ?? 0, sevenPct ?? 0);
  const quotaColor =
    !usage?.available
      ? undefined
      : maxQuota >= 90
        ? '#ef4444'
        : maxQuota >= 75
          ? '#d97706'
          : '#22c55e';

  const modeItems = useMemo<DropdownItem[]>(
    () =>
      MODES.map((m) => ({
        key: m.id,
        label: m.wire === currentMode ? `✓ ${m.label}` : m.label,
        onClick: () => {
          void invokeNativeUI('setPermissionMode', { mode: m.id, sessionId: selectedSessionId });
        },
      })),
    [currentMode, selectedSessionId],
  );

  const radius = 6;
  const circum = 2 * Math.PI * radius;
  const dashOffset = circum * (1 - ratio);

  return (
    <div data-pt-control-bar="1" title={status || undefined} {...sx(styles.bar)}>
      <div {...sx(styles.left)}>
        <DropdownMenu items={modeItems}>
          <button disabled={!selectedSessionId} type="button" {...sx(styles.chipBtn)}>
            <InfinityIcon size={13} />
            <span>{modeLabel}</span>
            <ChevronDown size={11} />
          </button>
        </DropdownMenu>

        <button
          disabled={!selectedSessionId}
          onClick={() => {
            if (selectedSessionId) {
              void invokeNativeUI(isConnected ? 'disconnectClaude' : 'connectClaude', {
                sessionId: selectedSessionId,
              });
            }
          }}
          title={
            isConnected
              ? language === 'en'
                ? 'Claude connected (click to disconnect)'
                : 'Claude 已连接（点击断开）'
              : language === 'en'
                ? 'Click to connect Claude session'
                : '点击连接当前会话后台'
          }
          type="button"
          {...sx(styles.chipBtn)}
        >
          <Laptop size={12} />
          <span {...sx(styles.dot, isConnected && styles.dotConnected)} />
          <span>
            {isConnected
              ? language === 'en'
                ? 'Connected'
                : '已连接'
              : language === 'en'
                ? 'Disconnected'
                : '未连接'}
          </span>
        </button>

        <button
          disabled={!cwd}
          onClick={() => {
            if (onOpenGitDir) onOpenGitDir();
            else if (cwd) void invokeNativeUI('openProjectFolder', { path: cwd, sessionId: selectedSessionId });
          }}
          title={cwd}
          type="button"
          {...sx(styles.chipBtn)}
        >
          <Folder size={12} />
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{cwdName}</span>
        </button>
      </div>

      <div {...sx(styles.right)}>
        {usage && (
          <span
            style={{ color: quotaColor, fontSize: 11.5, fontWeight: 500 }}
            title={
              usage.available
                ? `5h: ${usage.fiveHourPercent.toFixed(0)}% (${usage.fiveHourResetText})\n7d: ${usage.sevenDayPercent.toFixed(0)}% (${usage.sevenDayResetText})`
                : usage.error || (language === 'en' ? 'Plan usage unavailable' : '正在读取套餐用量')
            }
          >
            {usage.available
              ? `5h ${usage.fiveHourPercent.toFixed(0)}% · 7d ${usage.sevenDayPercent.toFixed(0)}%`
              : '5h — · 7d —'}
          </span>
        )}

        <button
          aria-expanded={ctxPopoverOpen}
          onClick={() => setCtxPopoverOpen((v) => !v)}
          type="button"
          {...sx(styles.chipBtn)}
        >
          <svg height="16" viewBox="0 0 16 16" width="16">
            <circle cx="8" cy="8" fill="none" r={radius} stroke="currentColor" strokeOpacity="0.22" strokeWidth="2" />
            <circle
              cx="8"
              cy="8"
              fill="none"
              r={radius}
              stroke="#22c55e"
              strokeDasharray={circum}
              strokeDashoffset={dashOffset}
              strokeLinecap="round"
              strokeWidth="2"
              transform="rotate(-90 8 8)"
            />
          </svg>
          <span>{ctxPctText}</span>
          <ChevronDown size={11} />
        </button>

        {ctxPopoverOpen && (
          <div {...sx(styles.ctxPopover)}>
            <div style={{ fontSize: 13, fontWeight: 600 }}>
              {language === 'en' ? 'Context & Cost' : '上下文与 API 等价成本'}
            </div>
            {shownModel && (
              <div {...sx(styles.ctxRow)}>
                <span>
                  {currentModel
                    ? (language === 'en' ? 'Current model' : '当前模型')
                    : (language === 'en' ? 'Last response model' : '最近回复模型')}
                </span>
                <span title={shownModel} {...sx(styles.modelLabel)}>{shownModel}</span>
              </div>
            )}
            <div {...sx(styles.ctxRow)}>
              <span style={{ color: 'var(--lobe-color-text-secondary)' }}>Context</span>
              <span title={contextUsed > 0 ? `${contextUsed.toLocaleString()} / ${contextWindow.toLocaleString()}` : undefined}>
                {contextUsed > 0 ? `${formatTokens(contextUsed)} / ${formatTokens(contextWindow)}` : '—'}
              </span>
            </div>
            {(activeSession?.contextBreakdown ?? []).map((item) => (
              <div key={item.category} {...sx(styles.ctxRow)}>
                <span style={{ color: 'var(--lobe-color-text-tertiary)' }}>
                  {item.label || item.category}
                </span>
                <span title={item.tokens.toLocaleString()}>{formatTokens(item.tokens)}</span>
              </div>
            ))}
            {modelBreakdown && <ModelUsageTable breakdown={modelBreakdown} language={language} />}
            {activeSession?.apiCostAvailable && (
              <div
                style={{
                  borderTop: '1px solid var(--lobe-color-border-secondary)',
                  display: 'flex',
                  fontSize: 12,
                  justifyContent: 'space-between',
                  paddingTop: 6,
                }}
              >
                <span style={{ color: 'var(--lobe-color-text-secondary)' }}>
                  {hasUnpricedModels
                    ? (language === 'en' ? 'Priced subtotal' : '已计价小计')
                    : (language === 'en' ? 'Est. API Cost' : 'API 等价成本')}
                </span>
                <span style={{ fontWeight: 600 }}>
                  {formatCost(activeSession.apiEquivalentCostUSD)}
                </span>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
});

ControlBar.displayName = 'ControlBar';
