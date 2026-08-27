import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy, StrategyOptions } from 'passport-jwt';
import { AuthService } from './auth.service';

/**
 * JwtStrategy — проверка JWT payload.
 *
 * Токен берётся из Bearer-заголовка ИЛИ из httpOnly cookie `auth_token`
 * (обратно-совместимо: старые Bearer-клиенты продолжают работать).
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(private readonly authService: AuthService) {
    const opts: StrategyOptions = {
      jwtFromRequest: ExtractJwt.fromExtractors([
        ExtractJwt.fromAuthHeaderAsBearerToken(),
        (req) => req?.cookies?.auth_token ?? null,
      ]),
      ignoreExpiration: false,
      secretOrKey: process.env.JWT_SECRET || 'dev-secret-change-me',
    };
    super(opts);
  }

  async validate(payload: any) {
    const user = await this.authService.validateJwtPayload(payload);
    if (!user) {
      throw new UnauthorizedException();
    }
    return { id: payload.sub, login: payload.login };
  }
}