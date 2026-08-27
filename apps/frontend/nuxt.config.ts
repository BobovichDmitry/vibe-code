// https://nuxt.com/docs/api/configuration/nuxt-config
//
// Nuxt 3 (SSR) — edge-сервис на порту 3000.
// Backend (Nest) — внутренний API на 3001; Nuxt проксирует /api/** туда.
//
// runtimeConfig:
//   - public.apiBase = '/api'         — клиентский fetch (через Nitro-прокси);
//   - apiBase (server-only)           — серверный fetch при SSR (прямой http://backend:3001/api).
//
// Переменные окружения (переопределяют дефолты):
//   NUXT_PUBLIC_API_BASE  — клиентский base (по умолчанию '/api');
//   NUXT_API_BASE         — серверный base (по умолчанию 'http://backend:3001/api',
//                           в dev — 'http://localhost:3001/api').
//
// Чтобы вынести frontend на отдельный сервер — достаточно указать
// NUXT_API_BASE на публичный URL backend (без правок кода).

const isProd = process.env.NODE_ENV === 'production';
const SERVER_API_BASE =
  process.env.NUXT_API_BASE ||
  (isProd ? 'http://backend:3001/api' : 'http://localhost:3001/api');

export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  dev: true,

  ssr: true,

  // Публичная часть (/, /login) — полноценный SSR.
  // /admin — целевой ориентир тоже SSR (меню/хром админки приходят готовыми).
  // Если cookie-auth окажется рискованным — можно переключить admin на CSR-shell
  // через routeRules: { '/admin/**': { ssr: false } }. Сейчас оставляем SSR.
  routeRules: {
    // Прокси /api/** → backend (Nitro проксирует на сервере; клиент идёт через свой же origin).
    '/api/**': { proxy: `${SERVER_API_BASE.replace(/\/$/, '')}/**` },
  },

  runtimeConfig: {
    // server-only (НЕ утекает в клиентский бандл)
    apiBase: SERVER_API_BASE,
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE || '/api',
    },
  },

  app: {
    head: {
      htmlAttrs: { lang: 'ru' },
      meta: [
        { charset: 'utf-8' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      ],
      link: [{ rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    },
  },

  css: ['~/assets/css/style.css'],

  postcss: {
    plugins: {
      tailwindcss: {},
      autoprefixer: {},
    },
  },

  typescript: {
    strict: true,
    typeCheck: false, // typecheck запускаем отдельно (nuxi typecheck / vue-tsc)
  },

  // В dev Nuxt слушает 3000; backend на 3001.
  devServer: {
    port: 3000,
  },

  // Nitro: в проде порт задаётся через NITRO_PORT env (см. Dockerfile.frontend),
  // хост — NITRO_HOST=0.0.0.0. Здесь только dev-настройки.

  // Nuxt 3 авто-импортит composables/, components/, middleware/, plugins/ —
  // явно указывать dirs не нужно. Псевдоним '~' и '@' → корень apps/frontend.
});