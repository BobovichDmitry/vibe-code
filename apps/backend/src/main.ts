import './env';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { NestExpressApplication } from '@nestjs/platform-express';
import * as cookieParser from 'cookie-parser';
import { AppModule } from './app.module';
import { ensureDatabaseExists } from './database/ensure-database';

/**
 * Точка входа Nest.js (API на /api).
 *
 * Backend — отдельный сервис на порту 3001 (по умолчанию; переопределяется
 * PORT из .env / .env.local, см. env.ts). Frontend (Nuxt SSR) работает на
 * порту 3000 (edge, за nginx-proxy по умолчанию) и
 * проксирует /api/** на этот backend через nitro routeRules.
 *
 * Cookie-auth: httpOnly cookie `auth_token` ставится на /api/auth/login
 * и читается JwtAuthGuard (наряду с обратно-совместимым Bearer).
 * Поэтому здесь подключается cookie-parser.
 *
 * Раздача статики frontend/dist убрана — теперь это делает Nuxt (Nitro).
 */
async function bootstrap() {
  // postgres: если DB_DATABASE ещё не существует (том postgres был
  // проинициализирован с другим именем) — создаём до инициализации TypeORM.
  await ensureDatabaseExists();

  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // CORS: из CORS_ORIGIN (comma-separated). По умолчанию — Nuxt-origin (dev).
  const corsOrigin = process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(',').map((o) => o.trim())
    : ['http://localhost:3000'];

  app.enableCors({
    origin: corsOrigin,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
  });

  // Cookie-parser — нужен для чтения httpOnly auth_token в JwtAuthGuard.
  app.use(cookieParser());

  app.setGlobalPrefix('api');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
    }),
  );

  // Порт — PORT из .env / .env.local. Nuxt (по умолчанию 3000) проксирует /api → сюда.
  const port = process.env.PORT || 3001;
  await app.listen(port);
  console.log(`Backend (API) running on http://localhost:${port}`);
}
bootstrap();