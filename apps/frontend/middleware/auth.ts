import { useAuth } from '~/composables/useAuth';

/**
 * middleware/auth — защита /admin/**. Редирект на /login если нет cookie.
 * Работает и на сервере (SSR), и на клиенте.
 *
 * httpOnly `auth_token` читается только на сервере (useCookie из заголовков).
 * На клиенте httpOnly cookie не виден, поэтому ориентируемся на visible-флаг
 * `auth_logged_in` (ставится вместе с auth_token на login). Флаг не содержит
 * секрета — это просто сигнал «залогинен». Реальная валидация токена — через
 * fetchUser (запрос /api/auth/me; cookie отправляется автоматически).
 */
export default defineNuxtRouteMiddleware(async () => {
  const { loggedInFlag, token, user, fetchUser } = useAuth();

  // Быстрая проверка: нет флага (клиент) и нет токена (сервер) → редирект.
  const hasSignal = import.meta.server
    ? !!token.value
    : loggedInFlag.value === '1';

  if (!hasSignal && !user.value) {
    return navigateTo('/login');
  }

  // Если user ещё не загружен — валидируем через backend.
  if (!user.value) {
    await fetchUser();
    if (!user.value) {
      return navigateTo('/login');
    }
  }
});