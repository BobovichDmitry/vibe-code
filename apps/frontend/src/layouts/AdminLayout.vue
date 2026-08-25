<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAuth } from '@/composables/useAuth';
import ThemeToggle from '@/components/ThemeToggle.vue';

/**
 * AdminLayout — layout админ-панели с ЛЕВЫМ вертикальным сайдбаром
 * (по образцу agent-hosted). Сайдбар содержит:
 *   - вертикальную навигацию (пока только «Пользователи» с иконкой);
 *   - внизу: ThemeToggle, бейдж логина, кнопка «Выйти».
 *
 * Без отдельного хедера внутри сайдбара — навигация начинается сверху.
 *
 * Адаптив:
 *   - `lg+`: сайдбар стационарный (`sticky top-0 h-dvh`, w-64 слева), контент — остаток;
 *   - `< lg`: сайдбар скрыт, открывается бургером в шапке как overlay-drawer
 *     (scrim + выезд слева). Закрытие: клик по scrim / Esc / выбор пункта.
 *
 * Маршрут `/admin` редиректит на `admin-users` (страница «Пользователи»).
 */
const { user, logout } = useAuth();
const route = useRoute();
const router = useRouter();

/** Drawer открыт (актуально только на `< lg`). */
const sidebarOpen = ref(false);

/** SVG-path иконки (heroicons outline). */
const ICON_USERS =
  'M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z';
const ICON_ARROW_LEFT =
  'M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18';

const navItems = [
  { name: 'Пользователи', path: '/admin', icon: ICON_USERS },
];

// «Пользователи» — единственная страница админки, активна на всём разделе /admin.
const isActive = (path: string) => route.path === path || route.path.startsWith(path + '/') || route.path === path;

function navigate(path: string) {
  router.push(path);
  // На `< lg` выбор пункта закрывает overlay-drawer.
  sidebarOpen.value = false;
}

/** Esc закрывает drawer. */
function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && sidebarOpen.value) sidebarOpen.value = false;
}

/** Блокируем скролл фона при открытом drawer. */
let savedBodyOverflow = '';
watch(sidebarOpen, (open) => {
  if (typeof document === 'undefined') return;
  if (open) {
    savedBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
  } else {
    document.body.style.overflow = savedBodyOverflow;
  }
});

// Смена роута закрывает drawer (кнопка «назад» браузера).
watch(
  () => route.path,
  () => {
    sidebarOpen.value = false;
  },
);

/** Переход `< lg` → `lg+`: drawer не нужен, закрываем (иначе невидимый scrim + залоченный скролл). */
let lgMedia: MediaQueryList | null = null;
const onLgChange = (e: MediaQueryListEvent) => {
  if (e.matches) sidebarOpen.value = false;
};

onMounted(() => {
  window.addEventListener('keydown', onKeydown);
  lgMedia = window.matchMedia('(min-width: 1024px)');
  lgMedia.addEventListener('change', onLgChange);
});

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown);
  lgMedia?.removeEventListener('change', onLgChange);
  if (typeof document !== 'undefined') document.body.style.overflow = savedBodyOverflow;
});
</script>

<template>
  <div class="flex min-h-dvh bg-slate-50 transition-colors duration-200 dark:bg-slate-950">
    <!-- Scrim (только < lg): затемнение под drawer -->
    <div
      v-if="sidebarOpen"
      class="fixed inset-0 z-40 bg-black/40 lg:hidden"
      @click="sidebarOpen = false"
    />

    <!-- Sidebar: на lg+ стационарный (sticky, высота = viewport); на < lg — overlay-drawer.
         Без хедера внутри — навигация сверху, внизу ThemeToggle + логин + Выйти. -->
    <aside
      class="fixed inset-y-0 left-0 z-50 flex w-64 shrink-0 transform flex-col border-r border-slate-200 bg-white transition-transform duration-200 dark:border-slate-800 dark:bg-slate-950 lg:sticky lg:top-0 lg:h-dvh lg:translate-x-0"
      :class="sidebarOpen ? 'translate-x-0' : '-translate-x-full'"
    >
      <!-- Вертикальная навигация (с верхним отступом вместо хедера) -->
      <nav class="min-h-0 flex-1 overflow-y-auto px-2 py-4" aria-label="Навигация админ-панели">
        <!-- Вернуться в приложение -->
        <button
          class="mb-2 flex w-full items-center gap-2.5 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-medium text-slate-500 transition hover:bg-slate-100 hover:text-slate-900 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white"
          @click="navigate('/')"
        >
          <svg class="h-[18px] w-[18px] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" :d="ICON_ARROW_LEFT" />
          </svg>
          <span class="truncate">Вернуться в приложение</span>
        </button>

        <ul class="flex flex-col gap-1">
          <li v-for="item in navItems" :key="item.path">
            <button
              class="flex w-full items-center gap-2.5 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-medium transition"
              :class="isActive(item.path)
                ? 'bg-brand-600 text-white shadow-sm'
                : 'text-slate-600 hover:bg-slate-100 dark:text-slate-300 dark:hover:bg-slate-800'"
              :aria-current="isActive(item.path) ? 'page' : undefined"
              @click="navigate(item.path)"
            >
              <svg class="h-[18px] w-[18px] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                <path stroke-linecap="round" stroke-linejoin="round" :d="item.icon" />
              </svg>
              <span class="truncate">{{ item.name }}</span>
            </button>
          </li>
        </ul>
      </nav>

      <!-- Низ сайдбара: ThemeToggle + логин + Выйти -->
      <div class="shrink-0 border-t border-slate-200 px-3 py-3 dark:border-slate-800">
        <div class="mb-2 flex items-center justify-center">
          <ThemeToggle />
        </div>
        <div class="mb-2 truncate rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-center text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">
          {{ user?.login }}
        </div>
        <button
          @click="logout"
          class="flex w-full items-center justify-center gap-2 rounded-xl border border-red-200 px-3 py-2 text-sm font-medium text-red-600 transition hover:bg-red-50 dark:border-red-900/50 dark:text-red-300 dark:hover:bg-red-950/40"
        >
          <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15M12 9l-3 3m0 0 3 3m-3-3h12.75" /></svg>
          <span>Выйти</span>
        </button>
      </div>
    </aside>

    <!-- Правая колонка: компактная шапка (бургер на < lg) + контент -->
    <div class="flex min-w-0 flex-1 flex-col">
      <header class="sticky top-0 z-30 shrink-0 border-b border-slate-200/80 bg-white/85 backdrop-blur-xl transition-colors duration-200 dark:border-slate-800 dark:bg-slate-950/85 lg:hidden">
        <div class="flex items-center gap-2 px-3 py-2.5 sm:px-6">
          <button
            class="rounded-lg p-2 text-slate-600 transition hover:bg-slate-100 dark:text-slate-300 dark:hover:bg-slate-800"
            aria-label="Открыть меню"
            @click="sidebarOpen = true"
          >
            <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" /></svg>
          </button>
          <h1 class="truncate text-lg font-semibold text-slate-950 dark:text-white">Admin Panel</h1>
        </div>
      </header>

      <main class="mx-auto w-full max-w-7xl flex-1 px-3 py-4 sm:px-6 sm:py-6 lg:px-8">
        <router-view />
      </main>
    </div>
  </div>
</template>