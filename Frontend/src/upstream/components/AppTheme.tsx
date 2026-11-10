// Upstream: lobehub/lobehub@00167e7b0f014e640194be732dd251931d663874 (src/layout/GlobalProvider/AppTheme.tsx)
// Adapted for WKWebView native bridge without external CDN font fetches.

import { ConfigProvider, setLobeTheme, type NeutralColors, type PrimaryColors } from '@lobehub/ui';
import type { TranslationResources, TranslationResourcesMap } from '@lobehub/ui/i18n/types';
import { en, zhCn } from '@lobehub/ui/i18n';
import { cssVar } from '@lobehub/ui/stylex/cssVar.stylex';
import * as stylex from '@stylexjs/stylex';
import { domAnimation, LazyMotion } from 'motion/react';
import * as m from 'motion/react-m';
import { memo, useEffect, useMemo, type ReactNode } from 'react';

import type { ThemeAppearance, UILanguage } from '@/bridge/contracts';
import { sx } from '@/upstream/styles/sx';

const styles = stylex.create({
  app: {
    alignItems: 'stretch',
    backgroundColor: cssVar.colorBgLayout,
    color: cssVar.colorText,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    minHeight: '100%',
    overflow: 'hidden',
    position: 'relative',
    width: '100%',
  },
});

export interface AppThemeProps {
  appearance: ThemeAppearance;
  children?: ReactNode;
  language: UILanguage;
  neutralColor?: NeutralColors;
  primaryColor?: PrimaryColors;
}

const flattenLocale = (sections: Record<string, TranslationResources>): TranslationResources =>
  Object.assign({}, ...Object.values(sections));

const EN_RESOURCES = flattenLocale(en as Record<string, TranslationResources>);
const ZH_RESOURCES = flattenLocale(zhCn as Record<string, TranslationResources>);
const RESOURCES_MAP: TranslationResourcesMap = {
  'en-US': EN_RESOURCES,
  'zh-CN': ZH_RESOURCES,
};

export const AppTheme = memo<AppThemeProps>(
  ({ appearance, language, neutralColor = 'slate', primaryColor, children }) => {
    const locale = useMemo(() => (language === 'en' ? 'en-US' : 'zh-CN'), [language]);

    useEffect(() => {
      setLobeTheme({
        appearance,
        neutralColor,
        primaryColor,
      });
      document.documentElement.lang = language === 'en' ? 'en' : 'zh-Hans';
      document.documentElement.dataset.ptAppearance = appearance;
      document.documentElement.dataset.ptLanguage = language;
      document.documentElement.style.colorScheme = appearance;
    }, [appearance, language, neutralColor, primaryColor]);

    useEffect(() => {
      const { style } = document.documentElement;
      style.setProperty(
        '--lobe-font-family',
        "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'PingFang SC', 'Helvetica Neue', sans-serif",
      );
      style.setProperty(
        '--lobe-font-family-code',
        "'PrettyTermDisplay', ui-monospace, 'SF Mono', Menlo, Monaco, monospace",
      );
    }, []);

    return (
      <LazyMotion features={domAnimation}>
        <ConfigProvider
          config={{ imgUnoptimized: true }}
          enableCustomFonts={false}
          locale={locale}
          motion={m}
          resources={RESOURCES_MAP}
        >
          <div data-pt-theme-root="1" {...sx(styles.app)}>
            {children}
          </div>
        </ConfigProvider>
      </LazyMotion>
    );
  },
);

AppTheme.displayName = 'AppTheme';
