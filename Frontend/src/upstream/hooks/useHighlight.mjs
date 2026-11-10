// Adapted from @lobehub/ui 6.15.2 (MIT), es/hooks/useHighlight.mjs.
// Keep rendered HTML with its mounted component so closed conversations can be collected.
import { getCodeLanguageByInput } from '@lobehub/ui/es/Highlighter/const';
import { useHighlighterEngine } from '@lobehub/ui/es/Highlighter/engine';
import { escapeHtml, tokensToHtml } from '@lobehub/ui/es/Highlighter/tokens';
import { useMemo } from 'react';

const highlightToHtml = ({ highlights, theme }, text, language) => {
  try {
    const result = highlights.codeToTokens(text, { lang: language, theme });
    return tokensToHtml(result, theme.name);
  } catch (error) {
    console.error('Syntax highlighting failed:', error);
    return `<pre class="fallback"><code>${escapeHtml(text)}</code></pre>`;
  }
};

export const useHighlight = (text, { language, theme: themeId, streaming }) => {
  const safeText = text ?? '';
  const lang = (language ?? 'plaintext').toLowerCase();
  const matchedLanguage = useMemo(() => getCodeLanguageByInput(lang), [lang]);
  const engine = useHighlighterEngine(themeId);
  return useMemo(() => {
    if (streaming || !engine) return '';
    return highlightToHtml(engine, safeText, matchedLanguage);
  }, [engine, matchedLanguage, safeText, streaming]);
};
