import { Button } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { ArrowDown, MessageSquareText, Quote } from 'lucide-react';
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent } from 'react';
import { VList, type VListHandle } from 'virtua';

import { invokeNativeUI } from '@/bridge/native';
import { scrollAnchors, transcriptTurn, usePTSlice, useTranscriptTurn } from '@/bridge/store';
import type { UILanguage } from '@/bridge/contracts';
import { sx } from '@/upstream/styles/sx';

import { AssistantTurnView, UserTurnView } from './MessageItem';

const styles = stylex.create({
  root: {
    display: 'flex',
    flex: 1,
    minHeight: 0,
    overflow: 'hidden',
    position: 'relative',
  },
  scroller: {
    flex: 1,
    height: '100%',
    minHeight: 0,
    overflowY: 'auto',
    paddingBlock: 16,
    paddingLeft: 24,
    paddingRight: 30,
  },
  column: {
    marginInline: 'auto',
    maxWidth: 800,
    width: '100%',
  },
  emptyState: {
    alignItems: 'center',
    color: cssVar.colorTextTertiary,
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    justifyContent: 'center',
    minHeight: 280,
    textAlign: 'center',
  },
  backBottom: {
    alignItems: 'center',
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 99,
    borderStyle: 'solid',
    borderWidth: 1,
    bottom: 16,
    boxShadow: cssVar.boxShadowSecondary,
    color: cssVar.colorText,
    cursor: 'pointer',
    display: 'flex',
    height: 34,
    justifyContent: 'center',
    position: 'absolute',
    right: 26,
    width: 34,
    zIndex: 8,
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
    },
  },
  minimap: {
    alignItems: 'flex-end',
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    position: 'absolute',
    right: 8,
    top: '50%',
    transform: 'translateY(-50%)',
    zIndex: 6,
  },
  minimapTick: {
    backgroundColor: cssVar.colorFillSecondary,
    borderRadius: 2,
    cursor: 'pointer',
    height: 2,
    transition: 'width 0.14s ease, background-color 0.14s ease',
    width: 10,
  },
  minimapTickActive: {
    backgroundColor: cssVar.colorText,
    height: 2.5,
    width: 18,
  },
  minimapPopover: {
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    boxShadow: cssVar.boxShadowSecondary,
    maxHeight: 340,
    overflowY: 'auto',
    padding: 6,
    position: 'absolute',
    right: 28,
    top: '50%',
    transform: 'translateY(-50%)',
    width: 240,
    zIndex: 15,
  },
  minimapRow: {
    borderRadius: 8,
    color: cssVar.colorTextSecondary,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 12,
    justifyContent: 'space-between',
    paddingBlock: 6,
    paddingInline: 8,
    ':hover': {
      backgroundColor: cssVar.colorFillTertiary,
      color: cssVar.colorText,
    },
  },
  quoteFloat: {
    alignItems: 'center',
    backgroundColor: cssVar.colorBgElevated,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 10,
    borderStyle: 'solid',
    borderWidth: 1,
    boxShadow: cssVar.boxShadowSecondary,
    display: 'flex',
    gap: 6,
    padding: 4,
    position: 'fixed',
    zIndex: 40,
  },
});

export interface ChatListProps {
  onOpenFile: (path: string) => void;
  onReviewTurn: (turnIndex: number) => void;
}

const ChatRow = memo<ChatListProps & {
  id: string;
  language: UILanguage;
  onChartPreview: (id: string) => void;
  onQuote: (text: string) => void;
  sessionId: string;
}>(({ id, language, onChartPreview, onOpenFile, onQuote, onReviewTurn, sessionId }) => {
  const turn = useTranscriptTurn(id);
  const captureChartPreview = (event: MouseEvent) => {
    if (event.target instanceof Element && event.target.closest('.lobe-mermaid svg')) {
      onChartPreview(id);
    }
  };
  if (!turn) return null;
  return (
    <div onClickCapture={captureChartPreview} {...sx(styles.column)}>
      {turn.kind === 'user'
        ? <UserTurnView language={language} sessionId={sessionId} turn={turn} />
        : <AssistantTurnView
            language={language}
            onOpenFile={onOpenFile}
            onQuote={onQuote}
            onReviewTurn={onReviewTurn}
            sessionId={sessionId}
            turn={turn}
          />}
    </div>
  );
});

ChatRow.displayName = 'ChatRow';

const EMPTY_ROWS: readonly string[] = [];

function FollowOutput({ id, onChange }: { id: string; onChange: () => void }) {
  const row = useTranscriptTurn(id);
  useLayoutEffect(() => {
    const frame = requestAnimationFrame(onChange);
    return () => cancelAnimationFrame(frame);
  }, [onChange, row]);
  return null;
}

export const ChatList = memo<ChatListProps>(({ onOpenFile, onReviewTurn }) => {
  const language = usePTSlice('language');
  const transcriptRows = usePTSlice('turnIds');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const setComposerQuote = usePTSlice('setComposerQuote');
  const sessionId = usePTSlice('transcript').sessionId;
  const rowIds = selectedSessionId === sessionId ? transcriptRows : EMPTY_ROWS;
  const listRef = useRef<VListHandle>(null);
  const nearBottomRef = useRef(true);
  const restoringAnchor = useRef(false);
  const [showBackBottom, setShowBackBottom] = useState(false);
  const [minimapHover, setMinimapHover] = useState(false);
  const [activeTurnIdx, setActiveTurnIdx] = useState(0);
  const [quotePopup, setQuotePopup] = useState<{ text: string; x: number; y: number } | null>(null);
  const [chartPreviewRow, setChartPreviewRow] = useState('');
  const keepMounted = useMemo(() => {
    const index = chartPreviewRow ? rowIds.indexOf(chartPreviewRow) : -1;
    return index >= 0 ? [index] : undefined;
  }, [chartPreviewRow, rowIds]);

  const userTurns = useMemo(() => {
    const latest = [];
    for (let rowIndex = rowIds.length - 1; rowIndex >= 0 && latest.length < 24; rowIndex--) {
      const id = rowIds[rowIndex];
      if (!id.endsWith(':user')) continue;
      const turn = transcriptTurn(id);
      if (turn?.kind === 'user') latest.push({ rowIndex, turn });
    }
    return latest.reverse();
  }, [rowIds]);

  useLayoutEffect(() => {
    if (!chartPreviewRow) return;
    const selector = '.lobe-image-viewer-popup';
    let opened = Boolean(document.querySelector(selector));
    const observer = new MutationObserver(() => {
      const visible = Boolean(document.querySelector(selector));
      if (opened && !visible) setChartPreviewRow('');
      opened ||= visible;
    });
    observer.observe(document.body, { childList: true, subtree: true });
    const frame = requestAnimationFrame(() => {
      if (!opened && !document.querySelector(selector)) setChartPreviewRow('');
    });
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [chartPreviewRow, sessionId]);

  const handleScroll = useCallback((offset: number) => {
    const list = listRef.current;
    if (!list || restoringAnchor.current) return;
    const distance = list.scrollSize - offset - list.viewportSize;
    const near = distance < 120;
    nearBottomRef.current = near;
    setShowBackBottom(!near && list.scrollSize > list.viewportSize + 240);

    const anchor = list.findItemIndex(offset);
    const id = rowIds[anchor];
    if (id && sessionId) {
      scrollAnchors.set(sessionId, { atBottom: near, id, offset: offset - list.getItemOffset(anchor) });
    }
    const current = rowIds[list.findItemIndex(offset + 80)];
    if (current) setActiveTurnIdx(transcriptTurn(current)?.turnIndex ?? 0);
  }, [rowIds, sessionId]);

  const followOutput = useCallback(() => {
    const list = listRef.current;
    if (list && nearBottomRef.current && !restoringAnchor.current) {
      list.scrollTo(list.scrollSize);
    }
  }, []);

  const scrollToBottom = useCallback(() => {
    listRef.current?.scrollToIndex(rowIds.length - 1, { align: 'end', smooth: true });
    nearBottomRef.current = true;
    setShowBackBottom(false);
  }, [rowIds.length]);

  const jumpToTurn = useCallback((rowIndex: number) => {
    nearBottomRef.current = false;
    listRef.current?.scrollToIndex(rowIndex, { align: 'start', smooth: true });
    setMinimapHover(false);
  }, []);

  const firstRow = rowIds[0];
  useLayoutEffect(() => {
    if (!sessionId || !firstRow) return;
    const saved = scrollAnchors.get(sessionId);
    nearBottomRef.current = saved?.atBottom ?? true;
    restoringAnchor.current = true;
    const place = () => {
      const list = listRef.current;
      if (!list) return;
      const index = saved ? rowIds.indexOf(saved.id) : -1;
      if (saved && !saved.atBottom && index >= 0) {
        list.scrollToIndex(index, { align: 'start', offset: saved.offset });
        setShowBackBottom(true);
      } else {
        // scrollTo(scrollSize) 用的是尚未测量的估算总高度，落点会偏；按行号对齐到底部更准。
        list.scrollToIndex(rowIds.length - 1, { align: 'end' });
        setShowBackBottom(false);
      }
    };
    // 先在首帧绘制前定位，避免每次切换都先闪现对话顶部；
    // 下一帧行高测量完成后再校正一次。
    place();
    const frame = requestAnimationFrame(() => {
      place();
      restoringAnchor.current = false;
    });
    return () => {
      cancelAnimationFrame(frame);
      restoringAnchor.current = false;
    };
  }, [firstRow, sessionId]);

  useEffect(() => {
    const handleMouseUp = () => {
      const sel = window.getSelection();
      const text = sel?.toString().trim() || '';
      if (!text || !sel?.rangeCount) {
        setQuotePopup(null);
        return;
      }
      const rect = sel.getRangeAt(0).getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) {
        setQuotePopup(null);
        return;
      }
      setQuotePopup({
        text,
        x: Math.min(window.innerWidth - 180, Math.max(16, rect.left + rect.width / 2 - 50)),
        y: Math.max(54, rect.top - 40),
      });
    };
    document.addEventListener('mouseup', handleMouseUp);
    return () => document.removeEventListener('mouseup', handleMouseUp);
  }, []);

  const handleQuote = useCallback(
    (raw: string) => {
      const quoted = raw
        .split('\n')
        .map((line) => `> ${line}`)
        .join('\n');
      setComposerQuote(quoted);
      setQuotePopup(null);
      window.getSelection()?.removeAllRanges();
    },
    [setComposerQuote],
  );

  const renderRow = useCallback((id: string) => (
    <ChatRow
      id={id}
      key={id}
      language={language}
      onChartPreview={setChartPreviewRow}
      onOpenFile={onOpenFile}
      onQuote={handleQuote}
      onReviewTurn={onReviewTurn}
      sessionId={sessionId}
    />
  ), [handleQuote, language, onOpenFile, onReviewTurn, sessionId]);

  return (
    <div data-pt-chat-list="1" {...sx(styles.root)}>
      {rowIds.length ? (
        <>
          <VList
            data={rowIds}
            itemSize={240}
            key={sessionId}
            keepMounted={keepMounted}
            onScroll={handleScroll}
            ref={listRef}
            {...sx(styles.scroller)}
          >
            {renderRow}
          </VList>
          <FollowOutput id={rowIds[rowIds.length - 1]} onChange={followOutput} />
        </>
      ) : (
        <div {...sx(styles.scroller)}>
          <div {...sx(styles.emptyState)}>
            <MessageSquareText size={28} strokeWidth={1.5} />
            <div style={{ fontSize: 14, fontWeight: 500 }}>
              {selectedSessionId
                ? language === 'en'
                  ? 'Waiting for Claude conversation messages...'
                  : '正在加载 Claude 会话记录…'
                : language === 'en'
                  ? 'Pick a conversation or click New Conversation'
                  : '从左侧选择一个会话，或开启新话题'}
            </div>
            {selectedSessionId && (
              <Button
                onClick={() => void invokeNativeUI('connectClaude', { sessionId: selectedSessionId })}
                size="small"
                type="default"
              >
                {language === 'en' ? 'Connect Claude Code' : '连接 Claude 后台'}
              </Button>
            )}
          </div>
        </div>
      )}

      {userTurns.length > 1 && (
        <div
          onMouseEnter={() => setMinimapHover(true)}
          onMouseLeave={() => setMinimapHover(false)}
          {...sx(styles.minimap)}
        >
          {userTurns.map(({ rowIndex, turn: t }) => (
            <div
              key={t.id}
              onClick={() => jumpToTurn(rowIndex)}
              title={t.text.slice(0, 60)}
              {...sx(styles.minimapTick, activeTurnIdx === t.turnIndex && styles.minimapTickActive)}
            />
          ))}

          {minimapHover && (
            <div {...sx(styles.minimapPopover)}>
              {userTurns.slice(-18).map(({ rowIndex, turn: t }) => (
                <div
                  key={`pop-${t.id}`}
                  onClick={() => jumpToTurn(rowIndex)}
                  {...sx(styles.minimapRow)}
                >
                  <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {t.text || (language === 'en' ? '[Image]' : '[图片]')}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {showBackBottom && (
        <button
          aria-label={language === 'en' ? 'Scroll to bottom' : '回到底部'}
          data-pt-back-bottom="1"
          onClick={scrollToBottom}
          type="button"
          {...sx(styles.backBottom)}
        >
          <ArrowDown size={16} />
        </button>
      )}

      {quotePopup && (
        <div {...sx(styles.quoteFloat, { left: quotePopup.x, top: quotePopup.y })}>
          <Button
            icon={<Quote size={13} />}
            onClick={() => handleQuote(quotePopup.text)}
            size="small"
            type="text"
          >
            {language === 'en' ? 'Quote' : '引用'}
          </Button>
        </div>
      )}
    </div>
  );
});

ChatList.displayName = 'ChatList';
