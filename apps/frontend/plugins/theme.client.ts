import { initThemeClient } from '~/composables/useTheme';

/**
 * theme.client — синхронизация темы на клиенте: системный preference,
 * зеркало localStorage → cookie, применение класса к <html>.
 */
export default defineNuxtPlugin(() => {
  initThemeClient();
});