<script setup lang="ts">
import { useAuth } from '@/composables/useAuth';
import { useBranding } from '@/composables/useBranding';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useRoute, useRouter } from 'vue-router';

const { user, logout } = useAuth();
const { title } = useBranding();
const route = useRoute();
const router = useRouter();

/** SVG-path иконок (heroicons outline) для пунктов меню. */
const ICON_USERS =
  'M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z';

const navItems = [
  { name: 'Пользователи', path: '/admin', icon: ICON_USERS },
];

const isActive = (path: string) => route.path === path || (path !== '/admin' && route.path.startsWith(path));
</script>

<template>
  <div class="min-h-screen bg-slate-50 transition-colors duration-200 dark:bg-slate-950">
    <header class="sticky top-0 z-40 border-b border-slate-200/80 bg-white/85 backdrop-blur-xl transition-colors duration-200 dark:border-slate-800 dark:bg-slate-950/85">
      <div class="mx-auto flex max-w-7xl flex-col gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <!-- Бренд-строка: бренд-блок слева, ThemeToggle + логин + Выйти справа -->
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="flex h-11 w-11 items-center justify-center rounded-2xl bg-brand-600 text-white shadow-soft">
              <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 11c0 1.657-1.343 3-3 3S6 12.657 6 11V8a6 6 0 1 1 12 0v3c0 3.314-2.686 6-6 6h-1"/><path stroke-linecap="round" stroke-linejoin="round" d="M9 14v2a3 3 0 1 0 6 0v-2"/>
              </svg>
            </div>
            <div>
              <h1 class="text-xl font-semibold text-slate-950 dark:text-white">{{ title }}</h1>
              <p class="text-sm text-slate-500 dark:text-slate-400">Admin Panel</p>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <ThemeToggle />
            <span class="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">{{ user?.login }}</span>
            <button @click="logout" class="btn-secondary border-red-200 text-red-600 hover:bg-red-50 dark:border-red-900/50 dark:text-red-300 dark:hover:bg-red-950/40">Выйти</button>
          </div>
        </div>

        <!-- Горизонтальное меню навигации -->
        <nav class="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1" aria-label="Навигация админ-панели">
          <button
            v-for="item in navItems"
            :key="item.path"
            @click="router.push(item.path)"
            class="flex items-center gap-2 whitespace-nowrap rounded-xl px-4 py-2.5 text-sm font-medium transition"
            :class="isActive(item.path)
              ? 'bg-brand-600 text-white shadow-sm'
              : 'border border-slate-200 bg-white text-slate-600 hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800'"
            :aria-current="isActive(item.path) ? 'page' : undefined"
          >
            <svg class="h-[18px] w-[18px] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path stroke-linecap="round" stroke-linejoin="round" :d="item.icon" />
            </svg>
            {{ item.name }}
          </button>
        </nav>
      </div>
    </header>

    <main class="mx-auto max-w-7xl px-4 py-4 sm:px-6 sm:py-6 lg:px-8">
      <router-view />
    </main>
  </div>
</template>