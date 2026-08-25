import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { join } from 'path';
import { ENTITIES } from './entities';

/**
 * Безопасный парсинг boolean-переменной окружения.
 * 'true' | '1' | 'yes' → true, остальное → false.
 * Если переменная не задана — возвращает defaultValue.
 */
function parseBooleanEnv(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined || value === '') return defaultValue;
  return value.toLowerCase() === 'true' || value === '1' || value.toLowerCase() === 'yes';
}

const dbType = process.env.DB_TYPE || 'sqlite';

/** dev: synchronize=true (быстрая итерация); prod: synchronize=false → миграции */
const synchronize = parseBooleanEnv(process.env.DB_SYNCHRONIZE, true);

const databaseConfig =
  dbType === 'postgres'
    ? {
        type: 'postgres' as const,
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        username: process.env.DB_USERNAME || 'postgres',
        password: process.env.DB_PASSWORD || 'postgres',
        database: process.env.DB_DATABASE || 'vibe_setup_ui',
        entities: ENTITIES,
        synchronize,
        migrationsRun: !synchronize,
        migrations: [join(__dirname, '..', 'migrations', '*.{ts,js}')],
      }
    : {
        type: 'sqlite' as const,
        database: process.env.DB_SQLITE_PATH || './data/database.sqlite',
        entities: ENTITIES,
        synchronize,
        migrationsRun: !synchronize,
        migrations: [join(__dirname, '..', 'migrations', '*.{ts,js}')],
      };

@Module({
  imports: [
    TypeOrmModule.forRoot({
      ...databaseConfig,
      logging: process.env.DB_LOGGING === 'true',
    }),
  ],
})
export class DatabaseModule {}