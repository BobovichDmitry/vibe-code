import { Controller, Get } from '@nestjs/common';
import { Public } from '../auth/public.decorator';

/**
 * Публичный эндпоинт брендинга (без JWT).
 * Возвращает { title, subtitle, faviconUrl } из env BRAND_TITLE / BRAND_SUBTITLE /
 * BRAND_FAVICON_URL. Используется фронтендом (useBranding) для document.title,
 * подзаголовка бренда в хедере и favicon.
 */
@Controller('branding')
export class BrandingController {
  @Public()
  @Get()
  getBranding() {
    return {
      title: process.env.BRAND_TITLE || 'VibeSetup UI',
      // Подзаголовок под названием в хедере. По умолчанию ПУСТОЙ (никакого
      // хардкода типа «Шаблоны приложения»): задаётся через env BRAND_SUBTITLE.
      subtitle: process.env.BRAND_SUBTITLE || '',
      faviconUrl: process.env.BRAND_FAVICON_URL || '/favicon.svg',
    };
  }
}