import { useIsDarkTheme, type ThemePreference } from '~/composables/useTheme';


/**
 * theme.server — ставит <html class="dark"> на сервере по cookie,
 * чтобы HTML уже приходил с правильной темой (без FOUC).
 *
 * Все композаблы (useCookie/useState/useIsDarkTheme/useHead) вызываются
 * внутри тела плагина — там доступен Nuxt-контекст.
 */
export default defineNuxtPlugin(() => {
  const themeCookie = useCookie<ThemePreference | null>('theme_preference');
  if (
    themeCookie.value === 'light' ||
    themeCookie.value === 'dark' ||
    themeCookie.value === 'system'
  ) {
    useState<ThemePreference>('theme').value = themeCookie.value;
  }

  // systemPrefersDark на сервере неизвестен (нет matchMedia) — оставляем false,
  // при 'system' берётся светлая тема. Гидратация совпадёт: клиентский plugin
  // перерисует после mount. FOUC минимален (только для 'system' + тёмная OS).
  const isDark = useIsDarkTheme();
  useHead({
    htmlAttrs: {
      class: () => (isDark.value ? 'dark' : ''),
      style: () => `color-scheme: ${isDark.value ? 'dark' : 'light'};`,
    },
  });
});
