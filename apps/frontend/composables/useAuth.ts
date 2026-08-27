import { useApi } from '~/composables/useApi';

/**
 * useAuth — аутентификация на httpOnly cookie (SSR-aware).
 *
 * Два cookie (ставит backend на /api/auth/login):
 *   - `auth_token`     — httpOnly JWT. Браузер отправляет его автоматически
 *     на /api-запросы (same-origin). На сервере (SSR) читается через useCookie
 *     (из заголовков). На КЛИЕНТЕ httpOnly cookie через useCookie НЕ виден —
 *     поэтому для UI-индикаторов используем второй cookie.
 *   - `auth_logged_in` — visible-флаг "1" (без секрета). Читается useCookie
 *     и на сервере, и на клиенте → источник «залогинен?» без сетевого запроса.
 *
 * `user` — реактивный state (useState, гидрируется из SSR). Заполняется
 * fetchUser (валидация через /api/auth/me — cookie отправляется автоматически).
 *
 * Bearer-auth обратно совместим — старые клиенты/e2e работают через заголовок.
 */
const TOKEN_COOKIE = 'auth_token';
const LOGGED_IN_COOKIE = 'auth_logged_in';

interface AuthUser {
  id: number;
  login: string;
}

// Состояние — keyed-singleton через useState (один ref на ключ в рамках
// запроса/приложения). Создаётся ЛЕНИВО внутри useAuth(): вызывать Nuxt-
// композаблы на уровне модуля нельзя — нет Nuxt-контекста (SSR упадёт).

export function useAuth() {
  const user = useState<AuthUser | null>('auth:user', () => null);
  const loading = useState<boolean>('auth:loading', () => false);
  const error = useState<string | null>('auth:error', () => null);
  // httpOnly JWT — читается только на сервере (SSR). На клиенте всегда null
  // (httpOnly cookies не видны через document.cookie / useCookie).
  const token = useCookie<string | null>(TOKEN_COOKIE);
  // Visible-флаг «залогинен» — читается и на сервере, и на клиенте.
  const loggedInFlag = useCookie<string | null>(LOGGED_IN_COOKIE);

  const isAuthenticated = computed(
    () => !!user.value || loggedInFlag.value === '1',
  );

  const fetchUser = async () => {
    // Токен есть только на сервере (httpOnly). На клиенте полагаемся на то,
    // что браузер сам отправит cookie с /api-запросом. Поэтому проверяем
    // loggedInFlag (виден везде) — если его нет, запрос /me вернёт 401.
    if (import.meta.server && !token.value) {
      user.value = null;
      return null;
    }
    if (import.meta.client && loggedInFlag.value !== '1') {
      user.value = null;
      return null;
    }
    try {
      user.value = await useApi().request<AuthUser>('/auth/me');
      return user.value;
    } catch {
      user.value = null;
      return null;
    }
  };

  const login = async (data: { login: string; password: string }) => {
    loading.value = true;
    error.value = null;
    try {
      // /api/auth/login ставит httpOnly auth_token + visible auth_logged_in.
      await useApi().request('/auth/login', { method: 'POST', body: data });
      // useCookie на клиенте не авто-обновляется из Set-Cookie ответа —
      // синхронизируем флаг вручную (browser уже хранит cookie; пишем то же).
      if (import.meta.client) {
        loggedInFlag.value = '1';
      }
      await fetchUser();
      return true;
    } catch (e: any) {
      error.value = e?.data?.message || 'Ошибка входа';
      return false;
    } finally {
      loading.value = false;
    }
  };

  const logout = async () => {
    try {
      await useApi().request('/auth/logout', { method: 'POST' });
    } catch {
      // ignore — чистим локально в любом случае
    }
    if (import.meta.client) {
      loggedInFlag.value = null;
    }
    user.value = null;
    if (import.meta.client) {
      navigateTo('/login');
    }
  };

  return {
    token,
    loggedInFlag,
    user,
    loading,
    error,
    isAuthenticated,
    login,
    logout,
    fetchUser,
  };
}