import { Injectable, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ExtractJwt } from 'passport-jwt';
import { IS_PUBLIC_KEY } from './public.decorator';

/**
 * JwtAuthGuard — защита маршрутов JWT.
 *
 * Токен извлекается из двух источников (обратно-совместимо):
 *   1. Authorization: Bearer <token>  — старые клиенты/e2e, внешние API-клиенты;
 *   2. Cookie `auth_token`            — Nuxt SSR + браузер (httpOnly cookie).
 *
 * Это позволяет одновременно поддерживать cookie-auth (для SSR/браузера) и
 * Bearer-auth (для скриптов/тестов), не ломая существующих потребителей.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromExtractors([
        ExtractJwt.fromAuthHeaderAsBearerToken(),
        (req) => req?.cookies?.auth_token ?? null,
      ]),
    });
  }

  canActivate(context: ExecutionContext) {
    // @Public() — публичный маршрут, без JWT.
    const handler = context.getHandler();
    const controller = context.getClass();
    const isPublic = Reflect.getMetadata(IS_PUBLIC_KEY, handler)
      || Reflect.getMetadata(IS_PUBLIC_KEY, controller);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}