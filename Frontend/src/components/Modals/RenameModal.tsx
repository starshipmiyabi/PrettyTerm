import { Input, Modal } from '@lobehub/ui';
import { memo, useEffect, useState } from 'react';

import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';

export const RenameModal = memo(() => {
  const language = usePTSlice('language');
  const renameModalSession = usePTSlice('renameModalSession');
  const setRenameModalSession = usePTSlice('setRenameModalSession');
  const [title, setTitle] = useState('');

  useEffect(() => {
    setTitle(renameModalSession?.title || '');
  }, [renameModalSession]);

  const handleConfirm = async () => {
    if (!renameModalSession) return;
    await invokeNativeUI('renameSession', {
      sessionId: renameModalSession.sessionId,
      title: title.trim(),
    });
    setRenameModalSession(null);
  };

  return (
    <Modal
      cancelText={language === 'en' ? 'Cancel' : '取消'}
      okText={language === 'en' ? 'Save' : '保存'}
      onCancel={() => setRenameModalSession(null)}
      onOk={() => void handleConfirm()}
      open={Boolean(renameModalSession)}
      title={language === 'en' ? 'Rename Conversation' : '重命名会话'}
      width={420}
    >
      <div style={{ paddingBlock: 8 }}>
        <Input
          autoFocus
          onChange={(e) => setTitle(e.target.value)}
          onPressEnter={() => void handleConfirm()}
          placeholder={language === 'en' ? 'Enter title...' : '输入新标题（留空恢复默认）…'}
          value={title}
        />
      </div>
    </Modal>
  );
});

RenameModal.displayName = 'RenameModal';
