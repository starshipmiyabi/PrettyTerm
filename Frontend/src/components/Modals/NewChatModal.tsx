import { Button, Input, Modal, TextArea } from '@lobehub/ui';
import { FolderOpen } from 'lucide-react';
import { memo, useEffect, useState } from 'react';

import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';

export interface NewChatModalProps {
  onClose: () => void;
  open: boolean;
}

export const NewChatModal = memo<NewChatModalProps>(({ onClose, open }) => {
  const activeSession = usePTSlice('activeSession');
  const language = usePTSlice('language');
  const windowState = usePTSlice('windowState');
  const [cwd, setCwd] = useState('');
  const [prompt, setPrompt] = useState('');
  const [launching, setLaunching] = useState(false);

  useEffect(() => {
    if (open) {
      setCwd(activeSession?.cwd || windowState.defaultCwd || '');
      setPrompt('');
    }
  }, [activeSession?.cwd, open, windowState.defaultCwd]);

  const handleBrowse = async () => {
    const res = await invokeNativeUI<{ path?: string }>('chooseFolderForNewChat', {});
    if (res.ok && res.data?.path) {
      setCwd(res.data.path);
    }
  };

  const handleCreate = async () => {
    if (!cwd.trim()) return;
    setLaunching(true);
    await invokeNativeUI('startNewConversation', {
      cwd: cwd.trim(),
      prompt: prompt.trim(),
    });
    setLaunching(false);
    onClose();
  };

  return (
    <Modal
      cancelText={language === 'en' ? 'Cancel' : '取消'}
      confirmLoading={launching}
      okButtonProps={{ disabled: !cwd.trim() }}
      okText={language === 'en' ? 'Start Claude Conversation' : '创建并连接会话'}
      onCancel={onClose}
      onOk={() => void handleCreate()}
      open={open}
      title={language === 'en' ? 'New Claude Conversation' : '开启新 Claude 对话'}
      width={500}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingBlock: 8 }}>
        <div>
          <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 6 }}>
            {language === 'en' ? 'Project Folder' : '项目工作目录'}
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Input
              onChange={(e) => setCwd(e.target.value)}
              placeholder="/Users/..."
              style={{ flex: 1 }}
              value={cwd}
            />
            <Button icon={<FolderOpen size={14} />} onClick={() => void handleBrowse()}>
              {language === 'en' ? 'Browse...' : '选择目录…'}
            </Button>
          </div>
        </div>

        <div>
          <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 6 }}>
            {language === 'en' ? 'Initial Message (Optional)' : '首条消息（可选，留空直接建立空白连接）'}
          </div>
          <TextArea
            autoSize={{ maxRows: 6, minRows: 3 }}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder={
              language === 'en'
                ? 'What would you like Claude to work on?'
                : '输入开场指令，或者留空进入对话…'
            }
            value={prompt}
          />
        </div>
      </div>
    </Modal>
  );
});

NewChatModal.displayName = 'NewChatModal';
