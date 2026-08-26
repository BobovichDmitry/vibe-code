/**
 * Helpers для формирования Content-Disposition с RFC 5987 кодированием
 * не-ASCII имён: `attachment; filename="ascii-fallback"; filename*=UTF-8''<encoded>`.
 */

/** Удаляем управляющие символы и заменяем слэши/обратные слэши на подчёркивание. */
export function sanitizeFileName(fileName: string): string {
  const cleaned = fileName
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .replace(/[\\/]/g, '_')
    .trim();
  return cleaned || 'file';
}

/** ASCII-совместимый fallback (не-ASCII символы → '_'). */
export function toAsciiFileName(fileName: string): string {
  const normalized = fileName
    .normalize('NFKD')
    .replace(/[^\x20-\x7E]/g, '_')
    .replace(/["\\]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();
  return normalized || 'file';
}

/** RFC 5987 кодирование (encodeURIComponent + экранирование '()*). */
export function encodeRFC5987(fileName: string): string {
  return encodeURIComponent(fileName).replace(/['()*]/g, (char) => {
    return `%${char.charCodeAt(0).toString(16).toUpperCase()}`;
  });
}

/** Готовая строка Content-Disposition. */
export function buildContentDisposition(
  fileName: string,
  disposition: 'inline' | 'attachment' = 'inline',
): string {
  const safe = sanitizeFileName(fileName);
  const ascii = toAsciiFileName(safe);
  const utf8 = encodeRFC5987(safe);
  return `${disposition}; filename="${ascii}"; filename*=UTF-8''${utf8}`;
}