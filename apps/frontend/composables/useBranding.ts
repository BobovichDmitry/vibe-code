import { useApi } from '~/composables/useApi';

/**
 * useBranding — брендинг интерфейса (title вкладки + favicon).
 *
 * SSR-safe: грузит GET /api/branding через useAsyncData (данные приходят
 * с сервера в HTML) и применяет результат через useHead (<title>, <link rel=icon>).
 * Дефолты — на случай пустого ответа/ошибки сети (не роняем UI).
 */
const DEFAULT_TITLE = 'VibeSetup UI';
const DEFAULT_FAVICON = '/favicon.svg';

export function useBranding() {
  const { data: branding } = useAsyncData<{ title: string; faviconUrl: string }>(
    'branding',
    () => useApi().request<{ title: string; faviconUrl: string }>('/branding'),
    {
      default: () => ({ title: DEFAULT_TITLE, faviconUrl: '' }),
      transform: (b) => ({
        title: b?.title?.trim() || DEFAULT_TITLE,
        faviconUrl: b?.faviconUrl?.trim() || DEFAULT_FAVICON,
      }),
    },
  );

  const title = computed(() => branding.value?.title ?? DEFAULT_TITLE);
  const faviconUrl = computed(() => branding.value?.faviconUrl ?? DEFAULT_FAVICON);

  useHead({
    title: title,
    link: [{ rel: 'icon', type: 'image/svg+xml', href: faviconUrl }],
  });

  return { title, faviconUrl };
}