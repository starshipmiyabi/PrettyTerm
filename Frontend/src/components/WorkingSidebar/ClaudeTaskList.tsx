import { Button } from '@lobehub/ui';
import { useCallback, useEffect, useState } from 'react';

import type { ClaudeProcessTask, UILanguage } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';

interface TaskOutput {
  output: string;
  total_bytes: number;
  truncated: boolean;
}

const taskKey = (task: ClaudeProcessTask) => JSON.stringify([task.task_id, task.run_id]);

function ForegroundTask({ language, sessionId, task }: {
  language: UILanguage;
  sessionId: string;
  task: ClaudeProcessTask;
}) {
  const [moving, setMoving] = useState(false);
  const [error, setError] = useState('');
  const moveToBackground = async () => {
    setMoving(true);
    setError('');
    const result = await invokeNativeUI('backgroundClaudeTask', {
      sessionId,
      toolUseId: task.tool_use_id,
    });
    setMoving(false);
    if (!result.ok) setError(result.error ?? '');
  };

  return (
    <div>
      <div style={{ alignItems: 'center', display: 'flex', gap: 8, justifyContent: 'space-between' }}>
        <span style={{ minWidth: 0, overflowWrap: 'anywhere' }}>{task.description || task.task_id}</span>
        <Button loading={moving} onClick={moveToBackground} size="small">
          {language === 'en' ? 'Background' : '转到后台'}
        </Button>
      </div>
      {error && <div role="alert" style={{ color: 'var(--lobe-color-error)' }}>{error}</div>}
    </div>
  );
}

function BackgroundOutput({ language, sessionId, task, onClose }: {
  language: UILanguage;
  sessionId: string;
  task: ClaudeProcessTask;
  onClose: () => void;
}) {
  const [output, setOutput] = useState<TaskOutput>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const readOutput = useCallback(async () => {
    setLoading(true);
    setError('');
    const result = await invokeNativeUI<TaskOutput>('readClaudeTaskOutput', {
      sessionId,
      taskId: task.task_id,
    });
    if (result.ok && result.data) setOutput(result.data);
    else setError(result.error ?? '');
    setLoading(false);
  }, [sessionId, task.task_id]);

  useEffect(() => { void readOutput(); }, [readOutput]);

  return (
    <div>
      <div style={{ alignItems: 'center', display: 'flex', gap: 6 }}>
        <strong style={{ flex: 1, overflowWrap: 'anywhere' }}>{task.description || task.task_id}</strong>
        <Button loading={loading} onClick={() => void readOutput()} size="small">
          {language === 'en' ? 'Refresh' : '刷新'}
        </Button>
        <Button onClick={onClose} size="small" type="text">
          {language === 'en' ? 'Close' : '关闭'}
        </Button>
      </div>
      {error && <div role="alert" style={{ color: 'var(--lobe-color-error)' }}>{error}</div>}
      {output?.truncated && (
        <div style={{ color: 'var(--lobe-color-text-tertiary)' }}>
          {language === 'en' ? 'Showing the last 8 KiB' : '显示末尾 8 KiB'}
        </div>
      )}
      {output && (
        <pre style={{ maxHeight: 240, overflow: 'auto', whiteSpace: 'pre-wrap' }}>
          {output.output || (language === 'en' ? 'No output yet' : '暂无输出')}
        </pre>
      )}
    </div>
  );
}

export function ClaudeTaskList({ language, sessionId }: { language: UILanguage; sessionId: string }) {
  const snapshot = usePTSlice('claudeTasks');
  const [selected, setSelected] = useState<{ generation: string; task: ClaudeProcessTask }>();
  const current = snapshot.sessionId === sessionId;
  const foreground = current ? snapshot.foreground : [];
  const background = current ? snapshot.background : [];
  const outputTask = current && selected?.generation === snapshot.generation ? selected.task : undefined;

  return (
    <>
      {foreground.length > 0 && (
        <>
          <strong>{language === 'en' ? 'Running in foreground' : '前台运行'}</strong>
          {foreground.map((task) => (
            <ForegroundTask key={taskKey(task)} language={language} sessionId={sessionId} task={task} />
          ))}
        </>
      )}
      <strong>{language === 'en' ? 'Background processes' : '后台进程'}</strong>
      {background.length === 0 && (
        <span style={{ color: 'var(--lobe-color-text-tertiary)' }}>
          {language === 'en' ? 'No running background processes' : '暂无运行中的后台进程'}
        </span>
      )}
      {background.map((task) => (
        <div key={taskKey(task)} style={{ alignItems: 'center', display: 'flex', gap: 8 }}>
          <div style={{ flex: 1, minWidth: 0, overflowWrap: 'anywhere' }}>
            <div>{task.description || task.task_id}</div>
            <small style={{ color: 'var(--lobe-color-text-tertiary)' }}>{task.task_id} · {task.task_type}</small>
          </div>
          {task.task_type === 'local_bash' && (
            <Button
              onClick={() => setSelected({ generation: snapshot.generation, task })}
              size="small"
            >
              {language === 'en' ? 'Output' : '查看输出'}
            </Button>
          )}
        </div>
      ))}
      {outputTask && (
        <BackgroundOutput
          key={taskKey(outputTask)}
          language={language}
          onClose={() => setSelected(undefined)}
          sessionId={sessionId}
          task={outputTask}
        />
      )}
    </>
  );
}
