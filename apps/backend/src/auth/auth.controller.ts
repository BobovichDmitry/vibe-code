import {
  Controller,
  Post,
  Body,
  UseGuards,
  Get,
  Request,
  Patch,
  Res,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Response } from 'express';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { Public } from './public.decorator';

/**
 * Cookie-auth.
 *
 * Два cookie на /api/auth/login:
 *   - `auth_token`      — httpOnly, сам JWT (защищён от кражи через XSS/JS).
 *     Читается JwtAuthGuard (cookie-extractor) и отправляется браузером
 *     автоматически на все /api-запросы (same-origin). На сервере (SSR)
 *     Nuxt читает его через useCookie (из заголовков запроса).
 *   - `auth_logged_in`  — НЕ httpOnly, значение "1" (только флаг присутствия,
 *     без секрета). Нужен клиенту, чтобы UI знал «я залогинен?» без сетевого
 *     запроса (httpOnly auth_token клиент прочитать не может). JWT в нём НЕТ.
 *
 * Bearer-auth обратно совместим — старые клиенты/e2e работают через заголовок.
 */
const AUTH_COOKIE_NAME = 'auth_token';
const LOGGED_IN_FLAG_NAME = 'auth_logged_in';
const COOKIE_MAX_AGE_SECONDS = 24 * 60 * 60; // 24h — синхрон с JWT expiresIn

function isSecureCookie(): boolean {
  const explicit = process.env.COOKIE_SECURE;
  if (explicit !== undefined) return explicit === 'true';
  return false; // dev (http://localhost) — не secure
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * Логин. Возвращает { access_token } (обратно-совместимо) И ставит
   * httpOnly cookie auth_token + visible-флаг auth_logged_in.
   */
  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(
    @Body() loginDto: LoginDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { access_token } = await this.authService.validateLogin(loginDto);
    res.cookie(AUTH_COOKIE_NAME, access_token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: isSecureCookie(),
      maxAge: COOKIE_MAX_AGE_SECONDS * 1000,
      path: '/',
    });
    // Visible-флаг (без секрета) — чтобы клиентский UI знал о залогиненности.
    res.cookie(LOGGED_IN_FLAG_NAME, '1', {
      httpOnly: false,
      sameSite: 'lax',
      secure: isSecureCookie(),
      maxAge: COOKIE_MAX_AGE_SECONDS * 1000,
      path: '/',
    });
    return { access_token };
  }

  /** Текущий пользователь (JWT из cookie или Bearer). */
  @UseGuards(JwtAuthGuard)
  @Get('me')
  getMe(@Request() req) {
    return req.user;
  }

  /** Смена пароля. */
  @UseGuards(JwtAuthGuard)
  @Patch('password')
  async changePassword(
    @Request() req,
    @Body() changePasswordDto: ChangePasswordDto,
  ) {
    await this.authService.changePassword(req.user.id, changePasswordDto);
    return { message: 'Пароль успешно изменён' };
  }

  /**
   * Логаут — чистит оба cookie. Bearer-токен остаётся валидным на сервере
   * (stateless JWT), но браузер его больше не отправляет.
   */
  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  logout(@Res({ passthrough: true }) res: Response) {
    res.clearCookie(AUTH_COOKIE_NAME, { path: '/' });
    res.clearCookie(LOGGED_IN_FLAG_NAME, { path: '/' });
    return { message: 'Вы вышли из системы' };
  }
}