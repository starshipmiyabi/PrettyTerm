import { ActionIcon, Button, Input } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { Play, SquareTerminal, Trash2, X } from 'lucide-react';
import { memo, useEffect, useRef, useState } from 'react';

import { invokeNativeUI } from '@/bridge/native';
import { observeTerminalOutput, usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  drawer: {
    backgroundColor: cssVar.colorBgContainer,
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    display: 'flex',
    flexDirection: 'column',
    flexShrink: 0,
    height: 220,
    minHeight: 160,
    overflow: 'hidden',
  },
  header: {
    alignItems: 'center',
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    gap: 8,
    height: 36,
    justifyContent: 'space-between',
    paddingInline: 12,
  },
  tabPill: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillTertiary,
    borderRadius: 6,
    color: cssVar.colorText,
    display: 'inline-flex',
    fontSize: 12,
    fontWeight: 500,
    gap: 6,
    paddingBlock: 3,
    paddingInline: 8,
  },
  output: {
    color: cssVar.colorText,
    flex: 1,
    fontFamily: cssVar.fontFamilyCode,
    fontSize: 12,
    lineHeight: 1.5,
    margin: 0,
    overflow: 'auto',
    padding: 12,
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  },
  promptRow: {
    alignItems: 'center',
    borderTopColor: cssVar.colorBorderSecondary,
    borderTopStyle: 'solid',
    borderTopWidth: 1,
    display: 'flex',
    gap: 6,
    paddingBlock: 6,
    paddingInline: 10,
  },
});

export const TerminalDrawer = memo<{ onClose: () => void }>(({ onClose }) => {
  const activeSession = usePTSlice('activeSession');
  const activeTab = usePTSlice('activeTab');
  const language = usePTSlice('language');
  const terminalState = usePTSlice('terminalState');
  const windowState = usePTSlice('windowState');
  const [command, setCommand] = useState('');
  const outputRef = useRef<HTMLSpanElement>(null);
  const [hasOutput, setHasOutput] = useState(false);

  useEffect(() => {
    const unsubscribe = observeTerminalOutput((text, reset) => {
      const output = outputRef.current;
      if (!output) return;
      if (reset) output.textContent = text;
      else if (text) output.append(document.createTextNode(text));
      setHasOutput(Boolean(output.firstChild));
    });
    void invokeNativeUI('setTerminalVisible', { visible: true });
    return () => {
      unsubscribe();
      void invokeNativeUI('setTerminalVisible', { visible: false });
    };
  }, []);
  const cwd = activeSession?.cwd || windowState.defaultCwd || '~';
  const dirLabel = cwd.split('/').filter(Boolean).pop() || cwd;

  const runCmd = () => {
    const trimmed = command.trim();
    if (!trimmed) return;
    void invokeNativeUI('runTerminalCommand', {
      command: trimmed,
      cwd,
      tabId: activeTab?.id || '',
    });
    setCommand('');
  };

  return (
    <div data-pt-terminal-drawer="1" {...sx(styles.drawer)}>
      <div {...sx(styles.header)}>
        <div style={{ alignItems: 'center', display: 'flex', gap: 8 }}>
          <span {...sx(styles.tabPill)}>
            <SquareTerminal size={13} />
            <span>{dirLabel}</span>
          </span>
          <span style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 11.5 }}>{cwd}</span>
        </div>

        <div style={{ alignItems: 'center', display: 'flex', gap: 4 }}>
          <Button
            onClick={() =>
              void invokeNativeUI('openTerminalApp', { cwd, sessionId: activeSession?.sessionId || '' })
            }
            size="small"
            type="text"
          >
            {language === 'en' ? 'Open Terminal.app' : '打开系统终端'}
          </Button>
          <ActionIcon
            icon={Trash2}
            onClick={() => void invokeNativeUI('clearTerminalOutput', { tabId: activeTab?.id || '' })}
            size="small"
            title={language === 'en' ? 'Clear output' : '清空输出'}
          />
          <ActionIcon icon={X} onClick={onClose} size="small" />
        </div>
      </div>

      <pre {...sx(styles.output)}>
        <span ref={outputRef} />
        {!hasOutput &&
          `${windowState.hostName || 'mac'} % ${language === 'en' ? '(Type a shell command below to inspect project workspace)' : '（在下方输入 shell 命令快速查看工作区环境）'}`}
      </pre>

      <div {...sx(styles.promptRow)}>
        <span style={{ color: 'var(--lobe-color-text-tertiary)', fontFamily: 'var(--lobe-font-family-code)', fontSize: 12 }}>
          %
        </span>
        <Input
          onChange={(e) => setCommand(e.target.value)}
          onPressEnter={runCmd}
          placeholder={language === 'en' ? 'git status, ls -la, pwd...' : '输入命令，例如 git status / ls -la…'}
          size="small"
          style={{ flex: 1 }}
          value={command}
        />
        <Button
          icon={<Play size={12} />}
          loading={terminalState.running}
          onClick={runCmd}
          size="small"
          type="primary"
        >
          {language === 'en' ? 'Run' : '执行'}
        </Button>
      </div>
    </div>
  );
});

TerminalDrawer.displayName = 'TerminalDrawer';
