export type ThemePreference = 'light' | 'dark' | 'system';

/**
 * useTheme — управление тёмной/светлой темой (SSR-safe, без FOUC).
 *
 * Хранение: cookie `theme_preference` (доступна и на сервере, и на клиенте).
 * На сервере plugin/theme.server читает cookie и ставит <html class="dark">
 * через useHead — HTML уже приходит с правильным классом (без FOUC).
 * На клиенте plugin/theme.client синхронизируется с системным preference
 * (matchMedia) и localStorage (зеркало cookie для быстрого доступа).
 *
 * ВАЖНО: Nuxt-композаблы (useState и зависящие от них computed) нельзя
 * вызывать на уровне модуля — только внутри Nuxt-контекста (setup/plugin/
 * middleware). Поэтому состояние создаётся лениво через keyed-геттеры:
 * useState('theme') возвращает один и тот же ref в рамках запроса/приложения.
 */
const THEME_COOKIE = 'theme_preference';

/** Keyed-singleton состояние выбранной темы. Вызывать внутри Nuxt-контекста. */
function themeState() {
  return useState<ThemePreference>('theme', () => 'system');
}

/** Keyed-singleton «система предпочитает тёмную» (matchMedia, client-only). */
function systemDarkState() {
  return useState<boolean>('theme:system-dark', () => false);
}

/** computed «текущая тема тёмная?» — вызывать внутри Nuxt-контекста. */
export function useIsDarkTheme() {
  const theme = themeState();
  const systemPrefersDark = systemDarkState();
  return computed(
    () => theme.value === 'dark' || (theme.value === 'system' && systemPrefersDark.value),
  );
}

export function useTheme() {
  const theme = themeState();
  const isDark = useIsDarkTheme();
  const cookieTheme = useCookie<ThemePreference | null>(THEME_COOKIE, { readonly: false });

  const setTheme = (value: ThemePreference) => {
    theme.value = value;
    cookieTheme.value = value;
    if (import.meta.client) {
      try {
        localStorage.setItem(THEME_COOKIE, value);
      } catch {
        // ignore
      }
      applyHtmlClass(isDark.value);
    }
  };

  const toggleTheme = () => {
    setTheme(isDark.value ? 'light' : 'dark');
  };

  return {
    theme,
    setTheme,
    toggleTheme,
    isDark,
  };
}

/** Применить класс к <html> (client-only — на сервере это делает useHead в plugin). */
function applyHtmlClass(dark: boolean) {
  if (typeof document === 'undefined') return;
  document.documentElement.classList.toggle('dark', dark);
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
}

/** Инициализация темы на клиенте: системный preference + зеркало localStorage → state. */
export function initThemeClient() {
  if (typeof window === 'undefined') return;
  const theme = themeState();
  const systemPrefersDark = systemDarkState();

  const mql = window.matchMedia('(prefers-color-scheme: dark)');
  systemPrefersDark.value = mql.matches;

  // Зеркало localStorage → state (если есть).
  try {
    const saved = localStorage.getItem(THEME_COOKIE);
    if (saved === 'light' || saved === 'dark' || saved === 'system') {
      theme.value = saved;
    }
  } catch {
    // ignore
  }

  const isDark = () =>
    theme.value === 'dark' || (theme.value === 'system' && systemPrefersDark.value);

  const handleChange = (e: MediaQueryListEvent) => {
    systemPrefersDark.value = e.matches;
    if (import.meta.client) applyHtmlClass(isDark());
  };
  if (typeof mql.addEventListener === 'function') {
    mql.addEventListener('change', handleChange);
  } else {
    // Старые Safari.
    mql.addListener(handleChange);
  }

  applyHtmlClass(isDark());
}
