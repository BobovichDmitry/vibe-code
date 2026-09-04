import { useApi } from '~/composables/useApi';

/**
 * useBranding — брендинг интерфейса (title вкладки + подзаголовок + favicon).
 *
 * SSR-safe: грузит GET /api/branding через useAsyncData (данные приходят
 * с сервера в HTML) и применяет результат через useHead (<title>, <link rel=icon>).
 * Дефолты — на случай пустого ответа/ошибки сети (не роняем UI).
 * subtitle по умолчанию ПУСТОЙ (env BRAND_SUBTITLE не задан → в хедере не рендерится).
 */
const DEFAULT_TITLE = 'VibeSetup UI';
const DEFAULT_FAVICON = '/favicon.svg';
const DEFAULT_SUBTITLE = '';

interface Branding {
  title: string;
  subtitle: string;
  faviconUrl: string;
}

export function useBranding() {
  const { data: branding } = useAsyncData<Branding>(
    'branding',
    () => useApi().request<Branding>('/branding'),
    {
      default: () => ({ title: DEFAULT_TITLE, subtitle: DEFAULT_SUBTITLE, faviconUrl: '' }),
      transform: (b) => ({
        title: b?.title?.trim() || DEFAULT_TITLE,
        subtitle: b?.subtitle?.trim() || DEFAULT_SUBTITLE,
        faviconUrl: b?.faviconUrl?.trim() || DEFAULT_FAVICON,
      }),
    },
  );

  const title = computed(() => branding.value?.title ?? DEFAULT_TITLE);
  const subtitle = computed(() => branding.value?.subtitle ?? DEFAULT_SUBTITLE);
  const faviconUrl = computed(() => branding.value?.faviconUrl ?? DEFAULT_FAVICON);

  useHead({
    title: title,
    link: [{ rel: 'icon', type: 'image/svg+xml', href: faviconUrl }],
  });

  return { title, subtitle, faviconUrl };
}