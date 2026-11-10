import { lazy, Suspense, type ComponentProps } from 'react';
import type MarkdownComponent from '@lobehub/ui/es/Markdown/Markdown';
import type HighlighterComponent from '@lobehub/ui/es/Highlighter/Highlighter';
import type DiffComponent from '@lobehub/ui/es/CodeDiff/CodeDiff';

const LazyMarkdown = lazy(async () => {
  const [markdown, { default: styles }] = await Promise.all([
    import('@lobehub/ui/es/Markdown/Markdown'),
    import('@/assets/katex/katex.min.css?url'),
  ]);
  const stylesheet = document.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = styles;
  document.head.appendChild(stylesheet);
  return markdown;
});
const LazyHighlighter = lazy(() => import('@lobehub/ui/es/Highlighter/Highlighter'));
const LazyCodeDiff = lazy(() => import('@lobehub/ui/es/CodeDiff/CodeDiff'));

export function Markdown(props: ComponentProps<typeof MarkdownComponent>) {
  return <Suspense><LazyMarkdown {...props} /></Suspense>;
}

export function Highlighter(props: ComponentProps<typeof HighlighterComponent>) {
  return <Suspense><LazyHighlighter {...props} /></Suspense>;
}

export function CodeDiff(props: ComponentProps<typeof DiffComponent>) {
  return <Suspense><LazyCodeDiff {...props} /></Suspense>;
}
