/**
 * useApi — SSR-aware обёртка над $fetch для запросов к backend (Nest, /api).
 *
 * - Клиент: baseURL = public.apiBase ('/api') — браузер идёт на свой же origin,
 *   Nitro проксирует /api/** → backend (routeRules).
 * - Сервер (SSR): baseURL = apiBase ('http://localhost:3001/api' / 'http://backend:3001/api')
 *   — прямой server-to-server fetch, мимо CORS.
 * - При SSR пробрасываем cookie из входящего запроса к backend (чтобы
 *   защищённые роуты работали под SSR — middleware/auth и useAsyncData видели юзера).
 *
 * Путь передаётся БЕЗ /api (baseURL уже его содержит): request('/users/count').
 */
export function useApi() {
  const config = useRuntimeConfig();
  const baseURL = import.meta.server ? config.apiBase : config.public.apiBase;

  // При SSR — проксируем cookie входящего запроса на backend.
  const serverHeaders = import.meta.server
    ? useRequestHeaders(['cookie'])
    : ({} as Record<string, string>);

  function request<T = unknown>(url: string, opts: any = {}): Promise<T> {
    return $fetch<T>(url, {
      baseURL,
      ...opts,
      headers: {
        ...serverHeaders,
        ...opts.headers,
      },
    });
  }

  return { request };
}