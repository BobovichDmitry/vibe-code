import { Controller, Get } from '@nestjs/common';

/**
 * GET /api/health — публичный (без JWT) healthcheck-эндпоинт.
 *
 * Используется healthcheck'ами docker-compose и скриптом деплоя
 * 0downtime (docker/deploy_0downtime.sh): новый слот считается
 * готовым к переключению только когда /api/health отвечает 200.
 * Здесь НЕ должно быть обращений к БД/внешним сервисам — только
 * факт «процесс поднялся и HTTP отвечает».
 */
@Controller('health')
export class HealthController {
  @Get()
  check(): { status: string } {
    return { status: 'ok' };
  }
}
