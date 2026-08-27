<script setup lang="ts">
import { useBranding } from '~/composables/useBranding';

/**
 * app.vue — корень Nuxt-приложения.
 * Глобально грузит брендинг (GET /api/branding — публичный) и применяет
 * title/favicon через useHead (SSR-safe — приходит в HTML с сервера).
 * Роутинг и layout применяются автоматически (NuxtPage + NuxtLayout).
 */
useBranding();
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>