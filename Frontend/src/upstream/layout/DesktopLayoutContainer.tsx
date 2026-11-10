// Upstream: lobehub/lobehub@00167e7b0f014e640194be732dd251931d663874 (src/features/DesktopLayoutContainer/index.tsx)

import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { memo, type ReactNode } from 'react';

import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  outer: {
    boxSizing: 'border-box',
    display: 'flex',
    flex: 1,
    minHeight: 0,
    minWidth: 0,
    overflow: 'hidden',
    paddingBottom: 8,
    paddingRight: 8,
    transition: 'padding-left 0.2s ease',
  },
  outerCollapsed: {
    paddingLeft: 8,
  },
  outerExpanded: {
    paddingLeft: 0,
  },
  inner: {
    backgroundColor: cssVar.colorBgContainer,
    borderColor: cssVar.colorBorderSecondary,
    borderRadius: 12,
    borderStyle: 'solid',
    borderWidth: 1,
    boxSizing: 'border-box',
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    height: '100%',
    minHeight: 0,
    minWidth: 0,
    overflow: 'hidden',
    position: 'relative',
  },
});

export interface DesktopLayoutContainerProps {
  children: ReactNode;
  sidebarExpanded: boolean;
}

export const DesktopLayoutContainer = memo<DesktopLayoutContainerProps>(
  ({ children, sidebarExpanded }) => {
    return (
      <div {...sx(styles.outer, sidebarExpanded ? styles.outerExpanded : styles.outerCollapsed)}>
        <div {...sx(styles.inner)}>{children}</div>
      </div>
    );
  },
);

DesktopLayoutContainer.displayName = 'DesktopLayoutContainer';
