# Upstream Attribution (`lobehub/lobehub`)

- **Repository**: `https://github.com/lobehub/lobehub`
- **Commit**: `00167e7b0f014e640194be732dd251931d663874`
- **Copied / Adapted Paths**:
  - `plugins/vite/stylex.ts` & `plugins/vite/stylexEntryCss.ts` -> `Frontend/vite.config.ts` (StyleX unplugin + token module registration + `--lh-stylex` anchor CSS check)
  - `src/styles/stylex.css` -> `Frontend/src/upstream/styles/stylex.css`
  - `src/styles/sx.ts` -> `Frontend/src/upstream/styles/sx.ts`
  - `src/styles/global.css` -> `Frontend/src/upstream/styles/global.css` (adapted with Safari 16.0 `@media (min-device-width: 576px)` and `color-mix` fallback)
  - `src/layout/GlobalProvider/AppTheme.tsx` -> `Frontend/src/upstream/components/AppTheme.tsx` (adapted to AppKit native appearance/language bridge and local bundled font assets without external CDN links)

## Lobe UI

- **Package**: `@lobehub/ui@6.15.2`, MIT, `https://github.com/lobehub/lobe-ui`
- `es/hooks/useHighlight.mjs` -> `hooks/useHighlight.mjs`: retain upstream highlighting and theme behavior; memoize HTML for the mounted component instead of retaining it in the global rendered-content cache. `pt-mounted-highlight-results` in Vite resolves the upstream hook to this adaptation.
