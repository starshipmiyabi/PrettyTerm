import { Highlighter, Markdown } from '@/components/Conversation/RichContent';
import { ActionIcon, Button, Input } from '@lobehub/ui';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import {
  ChevronDown,
  ChevronRight,
  ExternalLink,
  File,
  FileCode2,
  Folder,
  FolderOpen,
  FolderSync,
  PanelLeftClose,
  PanelLeftOpen,
  RefreshCw,
  Search,
  X,
} from 'lucide-react';
import { memo, useCallback, useEffect, useState } from 'react';

import type { FileTreeNode } from '@/bridge/contracts';
import { invokeNativeUI } from '@/bridge/native';
import { usePTSlice } from '@/bridge/store';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  root: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minHeight: 0,
    overflow: 'hidden',
  },
  toolbar: {
    alignItems: 'center',
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    gap: 6,
    paddingBlock: 8,
    paddingInline: 10,
  },
  splitBody: {
    display: 'flex',
    flex: 1,
    minHeight: 0,
    overflow: 'hidden',
  },
  treeScroll: {
    flex: 1,
    minHeight: 0,
    minWidth: 0,
    overflowX: 'hidden',
    overflowY: 'auto',
    padding: 6,
  },
  treeWithPreview: {
    flex: '0 0 38%',
    maxWidth: 240,
  },
  treeHidden: {
    display: 'none',
  },
  nodeRow: {
    alignItems: 'center',
    borderRadius: 6,
    color: cssVar.colorText,
    cursor: 'pointer',
    display: 'flex',
    fontSize: 12.5,
    gap: 6,
    height: 27,
    paddingRight: 8,
    userSelect: 'none',
    ':hover': {
      backgroundColor: cssVar.colorFillQuaternary,
    },
  },
  nodeRowActive: {
    backgroundColor: cssVar.colorFillTertiary,
    fontWeight: 500,
  },
  previewPane: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minWidth: 0,
    overflow: 'hidden',
  },
  previewWithTree: {
    borderInlineStartColor: cssVar.colorBorderSecondary,
    borderInlineStartStyle: 'solid',
    borderInlineStartWidth: 1,
  },
  previewHeader: {
    alignItems: 'center',
    backgroundColor: cssVar.colorFillQuaternary,
    borderBottomColor: cssVar.colorBorderSecondary,
    borderBottomStyle: 'solid',
    borderBottomWidth: 1,
    display: 'flex',
    flexShrink: 0,
    fontSize: 12,
    gap: 6,
    justifyContent: 'space-between',
    paddingBlock: 6,
    paddingInline: 10,
  },
  previewBody: {
    flex: 1,
    minHeight: 0,
    overflow: 'auto',
    padding: 10,
  },
});

function extColor(name: string): string {
  const ext = name.split('.').pop()?.toLowerCase() || '';
  if (ext === 'ts' || ext === 'tsx') return '#3178c6';
  if (ext === 'py') return '#3776ab';
  if (ext === 'm' || ext === 'h' || ext === 'swift') return '#f05138';
  if (ext === 'md') return '#0891b2';
  if (ext === 'json') return '#a855f7';
  if (ext === 'css') return '#2563eb';
  return 'var(--lobe-color-text-tertiary)';
}

const TreeNodeRow = memo<{
  activePath: string;
  depth: number;
  expandedMap: Record<string, boolean>;
  fileTreeByPath: Record<string, FileTreeNode[]>;
  filterQuery: string;
  node: FileTreeNode;
  onSelectFile: (path: string) => void;
  onToggleDir: (path: string) => void;
}>(({ activePath, depth, expandedMap, fileTreeByPath, filterQuery, node, onSelectFile, onToggleDir }) => {
  const q = filterQuery.trim().toLowerCase();
  const isExpanded = Boolean(expandedMap[node.path]);
  const children = fileTreeByPath[node.path] ?? [];

  if (q && !node.isDirectory && !node.name.toLowerCase().includes(q)) {
    return null;
  }

  return (
    <div>
      <div
        onClick={() => (node.isDirectory ? onToggleDir(node.path) : onSelectFile(node.path))}
        role="button"
        tabIndex={0}
        title={node.path}
        {...sx(styles.nodeRow, activePath === node.path && styles.nodeRowActive, { paddingLeft: 6 + depth * 14 })}
      >
        <span style={{ alignItems: 'center', display: 'flex', flexShrink: 0, width: 14 }}>
          {node.isDirectory ? (
            isExpanded ? (
              <ChevronDown size={13} />
            ) : (
              <ChevronRight size={13} />
            )
          ) : null}
        </span>
        {node.isDirectory ? (
          isExpanded ? (
            <FolderOpen color="#1677ff" size={14} />
          ) : (
            <Folder color="#6b7280" size={14} />
          )
        ) : (
          <FileCode2 color={extColor(node.name)} size={14} />
        )}
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {node.name}
        </span>
      </div>

      {node.isDirectory &&
        isExpanded &&
        children.map((child) => (
          <TreeNodeRow
            key={child.path}
            activePath={activePath}
            depth={depth + 1}
            expandedMap={expandedMap}
            fileTreeByPath={fileTreeByPath}
            filterQuery={filterQuery}
            node={child}
            onSelectFile={onSelectFile}
            onToggleDir={onToggleDir}
          />
        ))}
    </div>
  );
});

TreeNodeRow.displayName = 'TreeNodeRow';

export const FilesPane = memo(() => {
  const activeSession = usePTSlice('activeSession');
  const activeTab = usePTSlice('activeTab');
  const filePreview = usePTSlice('filePreview');
  const fileTreeByPath = usePTSlice('fileTreeByPath');
  const language = usePTSlice('language');
  const selectedSessionId = usePTSlice('selectedSessionId');
  const windowState = usePTSlice('windowState');

  const rootPath = activeTab?.fileTreeRootPath || activeSession?.cwd || windowState.defaultCwd || '';
  const [filterQuery, setFilterQuery] = useState('');
  const [expandedMap, setExpandedMap] = useState<Record<string, boolean>>({});
  const [dismissedPreviewId, setDismissedPreviewId] = useState('');
  const [treeVisible, setTreeVisible] = useState(true);
  const showPreview = Boolean(filePreview.path && filePreview.requestId !== dismissedPreviewId);
  const toggleTreeLabel = treeVisible
    ? (language === 'en' ? 'Hide file tree' : '收起文件树')
    : (language === 'en' ? 'Show file tree' : '展开文件树');

  const tabId = activeTab?.id || '';
  const loadDir = useCallback((dirPath: string) => {
    if (!dirPath) return;
    void invokeNativeUI('listDirectory', { path: dirPath, rootPath, tabId });
  }, [rootPath, tabId]);

  useEffect(() => {
    if (rootPath && !fileTreeByPath[rootPath]) {
      loadDir(rootPath);
    }
  }, [fileTreeByPath, loadDir, rootPath]);

  const handleToggleDir = useCallback(
    (dirPath: string) => {
      const next = !expandedMap[dirPath];
      if (next && !fileTreeByPath[dirPath]) loadDir(dirPath);
      setExpandedMap((prev) => ({ ...prev, [dirPath]: next }));
    },
    [expandedMap, fileTreeByPath, loadDir],
  );

  const handleSelectFile = useCallback(
    (filePath: string) => {
      void invokeNativeUI('previewFile', { path: filePath, sessionId: selectedSessionId, tabId });
    },
    [selectedSessionId, tabId],
  );

  const rootItems = rootPath ? fileTreeByPath[rootPath] ?? [] : [];
  const rootName = rootPath ? rootPath.split('/').filter(Boolean).pop() || rootPath : language === 'en' ? 'Select Folder' : '选择目录';

  return (
    <div data-pt-files-pane="1" {...sx(styles.root)}>
      <div {...sx(styles.toolbar)}>
        <ActionIcon
          aria-controls="pt-file-tree"
          aria-expanded={treeVisible}
          aria-label={toggleTreeLabel}
          icon={treeVisible ? PanelLeftClose : PanelLeftOpen}
          onClick={() => setTreeVisible((visible) => !visible)}
          size="small"
          title={toggleTreeLabel}
        />
        <Button
          icon={<FolderSync size={13} />}
          onClick={() => void invokeNativeUI('chooseFileTreeRoot', {})}
          size="small"
          title={rootPath}
          type="text"
        >
          <span style={{ maxWidth: 110, overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {rootName}
          </span>
        </Button>

        <Input
          allowClear
          onChange={(e) => setFilterQuery(e.target.value)}
          placeholder={language === 'en' ? 'Filter files...' : '筛选文件…'}
          prefix={<Search size={12} />}
          size="small"
          style={{ flex: 1 }}
          value={filterQuery}
        />

        <ActionIcon
          icon={RefreshCw}
          onClick={() => rootPath && loadDir(rootPath)}
          size="small"
          title={language === 'en' ? 'Refresh directory' : '刷新目录'}
        />
      </div>

      <div {...sx(styles.splitBody)}>
        <div
          id="pt-file-tree"
          {...sx(styles.treeScroll, showPreview && styles.treeWithPreview, !treeVisible && styles.treeHidden)}
        >
          {rootItems.length === 0 ? (
            <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12, padding: 20, textAlign: 'center' }}>
              {rootPath
                ? language === 'en'
                  ? 'Empty directory'
                  : '目录为空或尚未展开'
                : language === 'en'
                  ? 'Choose a project folder to inspect files'
                  : '请先选择项目根目录'}
            </div>
          ) : (
            rootItems.map((node) => (
              <TreeNodeRow
                key={node.path}
                activePath={filePreview.path}
                depth={0}
                expandedMap={expandedMap}
                fileTreeByPath={fileTreeByPath}
                filterQuery={filterQuery}
                node={node}
                onSelectFile={handleSelectFile}
                onToggleDir={handleToggleDir}
              />
            ))
          )}
        </div>

        {showPreview && (
          <div data-pt-file-preview="1" {...sx(styles.previewPane, treeVisible && styles.previewWithTree)}>
            <div {...sx(styles.previewHeader)}>
              <div style={{ alignItems: 'center', display: 'flex', flex: 1, gap: 6, minWidth: 0 }}>
                <File size={13} />
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {filePreview.path.split('/').pop()}
                </span>
              </div>
              <ActionIcon
                icon={ExternalLink}
                onClick={() => void invokeNativeUI('revealInFinder', { path: filePreview.path })}
                size="small"
                title={language === 'en' ? 'Reveal in Finder' : '在 Finder 中显示'}
              />
              <ActionIcon icon={X} onClick={() => setDismissedPreviewId(filePreview.requestId)} size="small" />
            </div>

            <div {...sx(styles.previewBody)}>
              {filePreview.loading ? (
                <div style={{ color: 'var(--lobe-color-text-tertiary)', fontSize: 12 }}>
                  {language === 'en' ? 'Loading preview...' : '正在加载文件预览…'}
                </div>
              ) : filePreview.error ? (
                <div style={{ color: '#ef4444', fontSize: 12 }}>{filePreview.error}</div>
              ) : filePreview.payload?.kind === 'image' && filePreview.payload.dataUrl ? (
                <img
                  alt={filePreview.path}
                  src={filePreview.payload.dataUrl}
                  style={{ borderRadius: 8, maxWidth: '100%' }}
                />
              ) : filePreview.payload?.kind === 'markdown' ? (
                <Markdown enableLatex enableMermaid variant="default">
                  {filePreview.payload.content || ''}
                </Markdown>
              ) : filePreview.payload?.content !== undefined ? (
                <Highlighter
                  language={filePreview.payload.language || 'text'}
                  showLanguage={false}
                  variant="borderless"
                >
                  {filePreview.payload.content}
                </Highlighter>
              ) : filePreview.payload?.html ? (
                <div style={{ fontSize: 12.5, whiteSpace: 'pre-wrap' }}>
                  {filePreview.payload.name || filePreview.path}
                </div>
              ) : null}
            </div>
          </div>
        )}
      </div>
    </div>
  );
});

FilesPane.displayName = 'FilesPane';
