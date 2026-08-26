import './env';
import { DataSource } from 'typeorm';
import { ENTITIES } from './database/entities';

/**
 * Standalone DataSource для TypeORM CLI (migration:generate/run/revert).
 * Не используется Nest.js — только CLI-команды.
 * synchronize=false, migrationsRun=false — CLI управляет миграциями явно.
 */
const dbType = process.env.DB_TYPE || 'sqlite';

export const AppDataSource = new DataSource(
  dbType === 'postgres'
    ? {
        type: 'postgres' as const,
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        username: process.env.DB_USERNAME || 'postgres',
        password: process.env.DB_PASSWORD || 'postgres',
        database: process.env.DB_DATABASE || 'vibe_setup_ui',
        entities: ENTITIES,
        synchronize: false,
        migrationsRun: false,
        migrations: [__dirname + '/migrations/*.{ts,js}'],
      }
    : {
        type: 'sqlite' as const,
        database: process.env.DB_SQLITE_PATH || './data/database.sqlite',
        entities: ENTITIES,
        synchronize: false,
        migrationsRun: false,
        migrations: [__dirname + '/migrations/*.{ts,js}'],
      },
);