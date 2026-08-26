/**
 * Конфигурация S3, читается из process.env в FileModule (useFactory).
 * Не используем @nestjs/config — проект его не подключает.
 */
export interface S3Config {
  endpoint: string;
  publicUrl: string;
  region: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  keyPrefix: string;
  uploadExpires: number;
  downloadExpires: number;
  forcePathStyle: boolean;
}

export const S3_CONFIG = Symbol('S3_CONFIG');

function parseBooleanEnv(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined || value === '') return defaultValue;
  return value.toLowerCase() === 'true' || value === '1' || value.toLowerCase() === 'yes';
}

function parseIntOrDefault(value: string | undefined, defaultValue: number): number {
  const n = parseInt(value || '', 10);
  return Number.isFinite(n) && n > 0 ? n : defaultValue;
}

export function loadS3ConfigFromEnv(): S3Config {
  const endpoint = process.env.S3_ENDPOINT || '';
  const publicUrl = process.env.S3_PUBLIC_URL || endpoint;
  return {
    endpoint,
    publicUrl,
    region: process.env.S3_REGION || 'us-east-1',
    bucket: process.env.S3_BUCKET || '',
    accessKey: process.env.S3_ACCESS_KEY || '',
    secretKey: process.env.S3_SECRET_KEY || '',
    keyPrefix: (process.env.S3_KEY_PREFIX || '').replace(/\/+$/, ''),
    uploadExpires: parseIntOrDefault(process.env.S3_UPLOAD_EXPIRES, 600),
    downloadExpires: parseIntOrDefault(process.env.S3_DOWNLOAD_EXPIRES, 86400),
    forcePathStyle: parseBooleanEnv(process.env.S3_FORCE_PATH_STYLE, true),
  };
}