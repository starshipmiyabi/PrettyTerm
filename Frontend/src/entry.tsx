import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from '@/App';
import { installFrontendBridge, usePTSlice } from '@/bridge/store';
import { normalizeAppearance, normalizeLanguage } from '@/bridge/native';
import { AppTheme } from '@/upstream/components/AppTheme';
import bootStyles from '@/upstream/styles/boot.css?url';

function ThemedRoot() {
  const windowState = usePTSlice('windowState');
  return (
    <AppTheme
      appearance={normalizeAppearance(windowState.appearance)}
      language={normalizeLanguage(windowState.language)}
    >
      <App />
    </AppTheme>
  );
}

const mountNode = document.getElementById('root');
if (mountNode) {
  installFrontendBridge();
  const stylesheet = document.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = bootStyles;
  stylesheet.addEventListener('load', () => {
    createRoot(mountNode).render(
      <StrictMode>
        <ThemedRoot />
      </StrictMode>,
    );
  }, { once: true });
  document.head.appendChild(stylesheet);
}
