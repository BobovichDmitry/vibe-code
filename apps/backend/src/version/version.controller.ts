import { Controller, Get } from '@nestjs/common';

// package.json читается из корня репо (workspace root) — Nest компилируется в CommonJS.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const pkg = require('../../../../package.json');

/**
 * GET /api/version — публичный (без JWT) служебный эндпоинт.
 *
 * Нужен для проверки деплоя: по нему видно, какая версия приложения
 * реально запущена на сервере (curl https://<domain>/api/version).
 *
 * - version — версия из package.json (корень репо);
 * - commit — SHA коммита запущенной сборки (APP_COMMIT_SHA: CI проставляет
 *   автоматически; в ручном деплое — через EXTRA_DEPLOY_ENV_VARS);
 * - build — хардкод: меняется вручную в коде, когда нужно,
 *   чтобы у деплоя появился визуально отличный ответ.
 */
@Controller('version')
export class VersionController {
  @Get()
  getVersion(): { version: string; commit: string | null; build: number } {
    return {
      version: pkg.version as string,
      commit: process.env.APP_COMMIT_SHA ?? null,
      build: 1,
    };
  }
}
