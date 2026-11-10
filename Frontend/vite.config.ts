// StyleX plugin configuration adapted from lobehub/lobehub
// commit 00167e7b0f014e640194be732dd251931d663874 (plugins/vite/stylex.ts, plugins/vite/stylexEntryCss.ts)

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import stylex from '@stylexjs/unplugin/vite';
import react from '@vitejs/plugin-react';
import legacy from '@vitejs/plugin-legacy';
import { defineConfig, type Plugin, type PluginOption } from 'vite';

const frontendDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(frontendDir, '..');

const stylexTokenModules = [
  '@lobehub/ui/stylex/cssVar.stylex',
  '@lobehub/ui/stylex/media.stylex',
] as const;

const classNamePrefix = 'lh';
const stylexAnchorMarker = '--lh-stylex';

type BundleItem = {
  fileName: string;
  source?: string | Uint8Array;
  type: 'asset' | 'chunk';
};
type Bundle = Record<string, BundleItem>;

const readSource = (item: BundleItem) =>
  typeof item.source === 'string' ? item.source : new TextDecoder().decode(item.source);

const cssAssets = (bundle: Bundle) =>
  Object.values(bundle).filter((item) => item.type === 'asset' && item.fileName.endsWith('.css'));

function createStylexPlugin(isProd: boolean): PluginOption {
  const plugin = stylex({
    aliases: { '@/*': [path.join(frontendDir, 'src/*')] },
    classNamePrefix,
    dev: !isProd,
    // Preserve :dir() and logical rules so StyleX output stays deterministic.
    lightningcssOptions: {
      exclude: 4 | 524_288,
    },
    runtimeInjection: false,
    unstable_moduleResolution: {
      rootDir: frontendDir,
      type: 'commonJS',
    },
  });

  const plugins = (Array.isArray(plugin) ? plugin : [plugin]) as Array<Plugin & {
    __stylexCollectCss?: () => string;
  }>;
  for (const item of plugins) {
    delete item.config;
    const collectCss = item.__stylexCollectCss;
    if (collectCss) {
      // Preserve the URL embedded in the SystemJS entry by appending in place.
      item.generateBundle = {
        handler(_options, output) {
          const boot = cssAssets(output as unknown as Bundle)
            .find((asset) => readSource(asset).includes(stylexAnchorMarker));
          if (!boot) this.error('Missing StyleX boot stylesheet');
          boot.source = `${readSource(boot)}\n${collectCss()}`;
        },
        order: 'post',
      };
      delete item.writeBundle;
    }
    if (typeof item.buildStart === 'function' && typeof item.transform === 'function') {
      const buildStart = item.buildStart;
      const transform = item.transform;
      const require = createRequire(path.join(frontendDir, 'package.json'));
      item.buildStart = async function (options) {
        await buildStart.call(this, options);
        for (const tokenModule of stylexTokenModules) {
          const filename = require.resolve(tokenModule);
          await Reflect.apply(transform, this, [readFileSync(filename, 'utf8'), filename]);
        }
      };
    }
  }

  return plugins;
}

function addSafari16DeclarationFallback(css: string): string {
  // Rewrite any leftover CSS Media Queries Level 4 ranges (`width >= 576px`, etc.).
  let out = css
    .replaceAll(
      /\(\s*(device-width|width|height)\s*>=\s*([^)]+?)\s*\)/g,
      (_m, prop: string, val: string) => `(min-${prop}:${val.trim()})`,
    )
    .replaceAll(
      /\(\s*(device-width|width|height)\s*<=\s*([^)]+?)\s*\)/g,
      (_m, prop: string, val: string) => `(max-${prop}:${val.trim()})`,
    );

  // Preserve exact upstream linear() spring timings for Safari 17.2+ while giving
  // Safari 16.0 valid cubic-bezier fallbacks so transitions never drop cleanly.
  const springMatchMap: Array<[string, string]> = [
    ['--lobe-motion-spring-bouncy', 'cubic-bezier(0.34, 1.56, 0.64, 1)'],
    ['--lobe-motion-spring-smooth', 'cubic-bezier(0.22, 1, 0.36, 1)'],
    ['--lobe-motion-spring-snappy', 'cubic-bezier(0.2, 0.9, 0.3, 1)'],
  ];
  const capturedLinearRules: string[] = [];
  for (const [varName, bezier] of springMatchMap) {
    const varRegex = new RegExp(`(${varName}\\s*:\\s*)(linear\\([^)]+\\))`, 'g');
    out = out.replace(varRegex, (_m, prefix: string, linearVal: string) => {
      capturedLinearRules.push(`${varName}: ${linearVal};`);
      return `${prefix}${bezier}`;
    });
  }
  if (capturedLinearRules.length > 0) {
    out += `\n@supports (transition-timing-function: linear(0, 1)) {\n  :root, :host {\n    ${capturedLinearRules.join('\n    ')}\n  }\n}\n`;
  }

  // Provide Safari 16.0 foreground fallback before oklch(from ...) contrast rule.
  out = out.replaceAll(
    /(color:\s*oklch\(from[^;{}]+)(;|\})/g,
    (_m, decl: string, end: string) => `color:var(--lobe-color-text);${decl}${end}`,
  );

  // Provide Safari 16.0 fallbacks immediately before standard CSS properties using color-mix(),
  // while keeping the exact color-mix() declaration second for Safari 16.2+.
  out = out.replaceAll(
    /([{};])(outline|box-shadow|border-color|border-top-color|border-right-color|border-bottom-color|border-left-color|background-color|background|color|fill|stroke)\s*:\s*([^;{}]*color-mix\([^;{}]+)(;|\})/g,
    (_full, sep: string, prop: string, val: string, end: string) => {
      let fallback = 'var(--lobe-color-border)';
      if (val.includes('--lobe-color-info')) fallback = 'rgba(22, 119, 255, 0.55)';
      else if (val.includes('--lobe-color-error')) fallback = 'rgba(255, 77, 79, 0.55)';
      else if (val.includes('--lobe-color-warning')) fallback = 'rgba(250, 173, 20, 0.55)';
      else if (val.includes('--lobe-color-success')) fallback = 'rgba(82, 196, 26, 0.55)';
      else if (val.includes('--lobe-color-bg-elevated')) fallback = 'var(--lobe-color-bg-elevated)';
      else if (val.includes('--lobe-color-bg-layout')) fallback = 'var(--lobe-color-bg-layout)';
      else if (val.includes('--lobe-color-bg-container')) fallback = 'var(--lobe-color-bg-container)';
      else if (val.includes('--lobe-color-text')) fallback = 'rgba(128, 128, 128, 0.18)';
      else if (val.includes('currentcolor') || val.includes('currentColor')) {
        fallback = prop === 'color' ? 'inherit' : 'rgba(128, 128, 128, 0.28)';
      }

      if (prop === 'outline') {
        fallback = `2px solid ${fallback}`;
      } else if (prop === 'box-shadow') {
        fallback = `0 0 0 2px ${fallback}`;
      }
      return `${sep}${prop}:${fallback};${prop}:${val}${end}`;
    },
  );

  // Also ensure --lobe-fill-border-strong and theme color-mix tokens have Safari 16.0 fallbacks
  // guarded by @supports not so Safari 16.2+ uses exact upstream color-mix() values.
  out += `
@supports not (color: color-mix(in srgb, red 50%, blue)) {
  [data-theme='light'], [data-theme='light'] [data-lobe-ui] {
    --lobe-fill-border-strong: rgba(0, 0, 0, 0.24);
  }
  [data-theme='dark'], [data-theme='dark'] [data-lobe-ui] {
    --lobe-fill-border-strong: rgba(255, 255, 255, 0.24);
  }
  :root {
    --lobe-table-selected-bg: rgba(0, 0, 0, 0.04);
    --lobe-table-selected-hover-bg: rgba(0, 0, 0, 0.08);
  }
}
`;
  return out;
}

function safari16CssCompatPlugin(): Plugin {
  return {
    apply: 'build',
    generateBundle: {
      handler(_options, output) {
        const bundle = output as unknown as Bundle;
        for (const item of cssAssets(bundle)) {
          item.source = addSafari16DeclarationFallback(readSource(item));
        }
      },
      order: 'post',
    },
    name: 'pt-safari16-css-compat',
  };
}

function fileProtocolScripts(): Plugin {
  return {
    apply: 'build',
    name: 'pt-file-protocol-scripts',
    transformIndexHtml: {
      order: 'post',
      handler(html) {
        return html
          .replace(/(<(?:link|script)\b[^>]*?)\s+crossorigin(?=[\s>])/g, '$1')
          .replace(
            'System.import(document.getElementById',
            "if (location.protocol === 'file:') { const create = System.createScript; System.createScript = function(url) { const script = create.call(this, url); if (url.startsWith('file:')) script.removeAttribute('crossorigin'); return script; }; } System.import(document.getElementById",
          );
      },
    },
  };
}

function mountedHighlightResults(): Plugin {
  return {
    name: 'pt-mounted-highlight-results',
    enforce: 'pre',
    resolveId(source, importer) {
      if (importer?.includes('/@lobehub/ui/') && source.endsWith('/hooks/useHighlight.mjs')) {
        return path.join(frontendDir, 'src/upstream/hooks/useHighlight.mjs');
      }
    },
  };
}

export default defineConfig(({ mode }) => {
  const isProd = mode === 'production';

  return {
    base: './',
    build: {
      assetsInlineLimit: 0,
      cssCodeSplit: true,
      manifest: true,
      minify: 'terser',
      modulePreload: false,
      cssMinify: isProd ? 'lightningcss' : false,
      cssTarget: 'safari16',
      emptyOutDir: true,
      outDir: path.join(repoRoot, '.build/frontend'),
      rolldownOptions: {
        checks: {
          invalidAnnotation: false,
        },
        input: path.join(frontendDir, 'index.html'),
        output: {
          assetFileNames: (asset) =>
            // StyleX appends rules after Vite resolves the stylesheet URL.
            asset.names.some((name) => name.endsWith('.css'))
              ? 'assets/[name][extname]'
              : 'assets/[name]-[hash][extname]',
          chunkFileNames: 'assets/[name]-[hash].js',
          codeSplitting: true,
          entryFileNames: 'assets/[name]-[hash].js',
        },
      },
      sourcemap: false,
    },
    css: {
      lightningcss: {
        targets: { safari: 16 << 16 },
      },
    },
    define: {
      'process.env.NODE_ENV': JSON.stringify(isProd ? 'production' : 'development'),
    },
    plugins: [
      mountedHighlightResults(),
      createStylexPlugin(isProd),
      react(),
      safari16CssCompatPlugin(),
      legacy({
        targets: ['Safari >= 16'],
        renderModernChunks: false,
        polyfills: false,
      }),
      fileProtocolScripts(),
    ],
    resolve: {
      alias: {
        '@': path.join(frontendDir, 'src'),
      },
      dedupe: ['react', 'react-dom'],
    },
    root: frontendDir,
  };
});
