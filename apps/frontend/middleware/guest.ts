import { useAuth } from '~/composables/useAuth';

/**
 * middleware/guest — гостевые страницы (/login). Если уже авторизован —
 * редирект в /admin. Работает и на сервере, и на клиенте.
 *
 * На клиенте httpOnly auth_token не виден — используем visible-флаг
 * auth_logged_in (или user state, если уже загружен).
 */
export default defineNuxtRouteMiddleware(() => {
  const { token, loggedInFlag, user } = useAuth();
  const hasSignal = import.meta.server
    ? !!token.value
    : loggedInFlag.value === '1';
  if (hasSignal || user.value) {
    return navigateTo('/admin');
  }
});