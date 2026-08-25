import { Controller, Get } from '@nestjs/common';
import { Public } from '../auth/public.decorator';

/**
 * Публичный эндпоинт брендинга (без JWT).
 * Возвращает { title, faviconUrl } из env BRAND_TITLE / BRAND_FAVICON_URL.
 * Используется фронтендом (useBranding) для document.title и favicon.
 */
@Controller('branding')
export class BrandingController {
  @Public()
  @Get()
  getBranding() {
    return {
      title: process.env.BRAND_TITLE || 'VibeSetup UI',
      faviconUrl: process.env.BRAND_FAVICON_URL || '/favicon.svg',
    };
  }
}