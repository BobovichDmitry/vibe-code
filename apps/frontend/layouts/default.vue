<script setup lang="ts">
import { useAuth } from '~/composables/useAuth';
import { useBranding } from '~/composables/useBranding';
import ThemeToggle from '~/components/ThemeToggle.vue';

/**
 * layouts/default.vue — дефолтный layout для публичных/гостевых страниц.
 * Глобальный хедер с брендом, ThemeToggle и кнопкой «Админ» (если авторизован).
 * /admin/** использует layouts/admin.vue (свой сайдбар) — этот хедер там не нужен.
 */
const { isAuthenticated, logout } = useAuth();
const { title, subtitle } = useBranding();
</script>

<template>
  <div class="min-h-screen bg-slate-50 transition-colors duration-200 dark:bg-slate-950">
    <header
      v-if="isAuthenticated"
      class="sticky top-0 z-40 border-b border-slate-200/80 bg-white/80 backdrop-blur-xl transition-colors duration-200 dark:border-slate-800 dark:bg-slate-950/80"
    >
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <button class="flex items-center gap-3 text-left" @click="navigateTo('/')">
          <span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-brand-600 text-white shadow-soft">
            <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
            </svg>
          </span>
          <span>
            <span class="block text-lg font-semibold text-slate-950 dark:text-white">{{ title }}</span>
            <!-- Подзаголовок опционален (env BRAND_SUBTITLE): пустой по умолчанию,
                 не рендерится вовсе — никакого хардкода от сетапа. -->
            <span v-if="subtitle" class="block text-sm text-slate-500 dark:text-slate-400">{{ subtitle }}</span>
          </span>
        </button>

        <div class="flex items-center gap-2">
          <ThemeToggle />
          <NuxtLink
            to="/admin"
            class="inline-flex h-11 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M12 11c0 1.657-1.343 3-3 3S6 12.657 6 11V8a6 6 0 1 1 12 0v3c0 3.314-2.686 6-6 6h-1"/><path stroke-linecap="round" stroke-linejoin="round" d="M9 14v2a3 3 0 1 0 6 0v-2"/></svg>
            Админ
          </NuxtLink>
          <button
            v-if="isAuthenticated"
            @click="logout"
            class="inline-flex h-11 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
          >
            Выйти
          </button>
        </div>
      </div>
    </header>

    <main class="mx-auto flex min-h-[calc(100vh-88px)] max-w-7xl flex-col">
      <slot />
    </main>
  </div>
</template>