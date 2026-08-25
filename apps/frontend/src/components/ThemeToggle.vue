<script setup lang="ts">
import { useTheme } from '@/composables/useTheme';

const { theme, setTheme, toggleTheme, isDark } = useTheme();
</script>

<template>
  <div class="flex items-center gap-2">
    <!-- Light / System / Dark segmented control (hidden on small screens) -->
    <div class="hidden rounded-xl border border-slate-200 bg-slate-50 p-1 dark:border-slate-700 dark:bg-slate-900 sm:flex">
      <button
        @click="setTheme('light')"
        class="rounded-lg px-3 py-2 text-xs font-medium transition"
        :class="theme === 'light' ? 'bg-white text-slate-900 shadow-sm dark:bg-slate-800 dark:text-white' : 'text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white'"
      >Light</button>
      <button
        @click="setTheme('system')"
        class="rounded-lg px-3 py-2 text-xs font-medium transition"
        :class="theme === 'system' ? 'bg-white text-slate-900 shadow-sm dark:bg-slate-800 dark:text-white' : 'text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white'"
      >System</button>
      <button
        @click="setTheme('dark')"
        class="rounded-lg px-3 py-2 text-xs font-medium transition"
        :class="theme === 'dark' ? 'bg-white text-slate-900 shadow-sm dark:bg-slate-800 dark:text-white' : 'text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white'"
      >Dark</button>
    </div>
    <!-- Quick light/dark toggle button -->
    <button
      @click="toggleTheme"
      class="inline-flex h-11 w-11 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-600 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
      :aria-label="isDark ? 'Светлая тема' : 'Тёмная тема'"
    >
      <svg v-if="isDark" class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M21 12.79A9 9 0 1 1 11.21 3c0 .24-.01.48-.01.72A9 9 0 0 0 20.28 12c.24 0 .48 0 .72-.01Z"/></svg>
      <svg v-else class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25M12 18.75V21M4.72 4.72l1.59 1.59M17.69 17.69l1.59 1.59M3 12h2.25M18.75 12H21M4.72 19.28l1.59-1.59M17.69 6.31l1.59-1.59M15.75 12A3.75 3.75 0 1 1 8.25 12a3.75 3.75 0 0 1 7.5 0Z"/></svg>
    </button>
  </div>
</template>