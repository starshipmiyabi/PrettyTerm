import type { NativeUIBridgeReply, Surface, ThemeAppearance, UILanguage, WindowStateSnapshot } from './contracts';

interface WebKitMessageHandler {
  postMessage: (message: unknown) => Promise<unknown> | void;
}

interface PrettyTermWindow extends Window {
  __PRETTYTERM_INITIAL_STATE__?: WindowStateSnapshot;
  webkit?: {
    messageHandlers?: {
      prettyTermUI?: WebKitMessageHandler;
    };
  };
}

function getWin(): PrettyTermWindow {
  return window as PrettyTermWindow;
}

export function normalizeAppearance(input?: unknown): ThemeAppearance {
  if (typeof input === 'string') {
    return input.toLowerCase().includes('dark') ? 'dark' : 'light';
  }
  if (input && typeof input === 'object') {
    const obj = input as { appearance?: unknown; dark?: unknown; isDark?: unknown };
    if (obj.dark === true || obj.isDark === true) return 'dark';
    if (typeof obj.appearance === 'string') {
      return obj.appearance.toLowerCase().includes('dark') ? 'dark' : 'light';
    }
  }
  return 'light';
}

export function normalizeLanguage(input?: unknown): UILanguage {
  if (typeof input === 'string' && input.toLowerCase().startsWith('en')) {
    return 'en';
  }
  return 'zh-Hans';
}

export function normalizeSurface(input?: unknown): Surface {
  if (input === 'floating') return 'floating';
  const params = new URLSearchParams(window.location.search);
  return params.get('surface') === 'floating' ? 'floating' : 'main';
}

export function readInitialWindowState(): WindowStateSnapshot {
  const initial = getWin().__PRETTYTERM_INITIAL_STATE__ ?? {};
  return {
    ...initial,
    appearance: normalizeAppearance(initial.appearance ?? document.documentElement.dataset.theme),
    language: normalizeLanguage(initial.language ?? document.documentElement.lang),
    surface: normalizeSurface(initial.surface),
    version: initial.version ?? '1.0.0 (8)',
  };
}

export function hasNativeUIHandler(): boolean {
  return typeof getWin().webkit?.messageHandlers?.prettyTermUI?.postMessage === 'function';
}

export async function invokeNativeUI<T = Record<string, unknown>>(
  action: string,
  payload: Record<string, unknown> = {},
): Promise<NativeUIBridgeReply<T>> {
  const handler = getWin().webkit?.messageHandlers?.prettyTermUI;
  if (!handler || typeof handler.postMessage !== 'function') {
    return {
      action,
      error: 'prettyTermUI handler unavailable',
      ok: false,
    };
  }
  try {
    const result = await handler.postMessage({
      action,
      ...payload,
    });
    if (result && typeof result === 'object') {
      return result as NativeUIBridgeReply<T>;
    }
    return { action, data: result as T, ok: true };
  } catch (error) {
    return {
      action,
      error: error instanceof Error ? error.message : String(error),
      ok: false,
    };
  }
}

export function triggerWindowDrag(surface: Surface): void {
  void invokeNativeUI('windowDrag', { surface });
}
