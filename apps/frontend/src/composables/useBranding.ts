import { ref } from 'vue';
import { getBranding } from '@/api/branding';

/**
 * Брендинг интерфейса: название продукта (title) и favicon.
 *
 * Singleton (module-level): грузит `GET /api/branding` (публичный, без JWT)
 * один раз на старте приложения и применяет результат к DOM:
 *  - `document.title` — title вкладки браузера;
 *  - `<link rel="icon">` — favicon (пустой URL → дефолтный /favicon.svg).
 *
 * Реактивные `title`/`faviconUrl` используются шапками (AdminLayout, App.vue,
 * PublicView, LoginView). Дефолты — на случай пустого ответа/ошибки сети
 * (не роняем UI).
 */

const DEFAULT_TITLE = 'VibeSetup UI';
const DEFAULT_FAVICON = '/favicon.svg';

const title = ref<string>(DEFAULT_TITLE);
const faviconUrl = ref<string>('');
let loaded = false;

function applyFavicon(rawUrl: string) {
  const href = rawUrl && rawUrl.trim() ? rawUrl.trim() : DEFAULT_FAVICON;
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) {
    link = document.createElement('link');
    link.rel = 'icon';
    document.head.appendChild(link);
  }
  link.href = href;
  // data: URI и абсолютные ссылки могут быть любым типом; для svg явно укажем,
  // чтобы браузер не пытался интерпретировать как x-icon.
  link.type = href.trim().toLowerCase().endsWith('.svg') ? 'image/svg+xml' : '';
}

function applyTitle(rawTitle: string) {
  const t = rawTitle && rawTitle.trim() ? rawTitle.trim() : DEFAULT_TITLE;
  title.value = t;
  document.title = t;
}

/** Применить новые значения брендинга к DOM и реактивному состоянию. */
export function applyBranding(next: { title?: string; faviconUrl?: string }) {
  if (typeof next.title === 'string') applyTitle(next.title);
  if (typeof next.faviconUrl === 'string') {
    faviconUrl.value = next.faviconUrl;
    applyFavicon(next.faviconUrl);
  }
}

/** Загрузить брендинг с бэкенда (один раз). Безопасно вызывать повторно. */
export async function loadBranding(force = false) {
  if (loaded && !force) return;
  loaded = true;
  try {
    const b = await getBranding();
    applyBranding({ title: b.title, faviconUrl: b.faviconUrl });
  } catch {
    // Бэкенд недоступен — оставляем дефолт.
    loaded = false;
  }
}

/** Singleton-доступ к реактивному title/faviconUrl для шапок и т.д. */
export function useBranding() {
  return { title, faviconUrl, loadBranding, applyBranding };
}