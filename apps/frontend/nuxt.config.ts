// https://nuxt.com/docs/api/configuration/nuxt-config
//
// Nuxt 3 (SSR) — edge-сервис на порту 3000 (по умолчанию).
// Backend (Nest) — внутренний API на 3001 (по умолчанию); Nuxt проксирует /api/** туда.
//
// Порты задаются через env-файлы в папках сервисов (и через внешнее окружение):
//   apps/frontend/.env.local →  PORT (порт самого frontend, dev-сервера)
//   apps/backend/.env.local  →  PORT (порт backend)
// Ссылки между сервисами — через NUXT_API_BASE (серверный base у frontend)
// и CORS_ORIGIN (разрешённый origin у backend).
//
// runtimeConfig:
//   - public.apiBase = '/api'         — клиентский fetch (через Nitro-прокси);
//   - apiBase (server-only)           — серверный fetch при SSR (прямой http://backend:3001/api).
//
// Переменные окружения (переопределяют дефолты):
//   PORT                  — порт dev-сервера (по умолчанию 3000, только для nuxt dev);
//   NUXT_PUBLIC_API_BASE  — клиентский base (по умолчанию '/api');
//   NUXT_API_BASE         — серверный base (по умолчанию 'http://backend:3001/api',
//                           в dev — 'http://localhost:3001/api').
//
// В проде порт задают NITRO_PORT/NITRO_HOST (Nitro слушает их в рантайме;
// devServer ниже — только для nuxt dev).
//
// Чтобы вынести frontend на отдельный сервер — достаточно указать
// NUXT_API_BASE на публичный URL backend (без правок кода).

import * as dotenv from 'dotenv';

// Локальные переопределения из .env.local (gitignored, рядом с этим конфигом).
// Nuxt CLI (c12) подгружает только `.env`, поэтому .env.local подтягиваем сами —
// по той же схеме, что и backend (см. apps/backend/src/env.ts).
// override: true — значения из .env.local сильнее одноимённых из .env и внешнего
// окружения (та же семантика, что у backend/src/env.ts).
// Для портов и NUXT_* это основной способ локальной настройки без правки кода.
dotenv.config({ path: '.env.local', override: true });

const isProd = process.env.NODE_ENV === 'production';
const SERVER_API_BASE =
  process.env.NUXT_API_BASE ||
  (isProd ? 'http://backend:3001/api' : 'http://localhost:3001/api');

// Порт dev-сервера: PORT из .env / .env.local, fallback 3000.
// Пустое/некорректное значение → 3000. (Кроме чтения здесь, nuxi сам читает
// NUXT_PORT/NITRO_PORT/PORT из реального окружения с более высоким приоритетом.)
const DEV_PORT = Number(process.env.PORT) || 3000;

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

  // Порт dev-сервера — из PORT (см. DEV_PORT выше); backend по умолчанию на 3001.
  devServer: {
    port: DEV_PORT,
  },

  // Nitro: в проде порт задаётся через NITRO_PORT env (см. Dockerfile.frontend),
  // хост — NITRO_HOST=0.0.0.0. Здесь только dev-настройки.

  // Nuxt 3 авто-импортит composables/, components/, middleware/, plugins/ —
  // явно указывать dirs не нужно. Псевдоним '~' и '@' → корень apps/frontend.
});