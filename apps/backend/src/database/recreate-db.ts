import '../env';
import { DataSource } from 'typeorm';
import { ENTITIES } from './entities';

/**
 * db:recreate — prod-prep утилита: дроп схемы + накат миграций с нуля.
 *
 * Отказывает на дефолтном dev-SQLite (./data/database.sqlite),
 * чтобы случайно не удалить локальную dev-БД.
 * Работает только через явные DB_* env-переменные (как в референсе).
 */

const dbType = process.env.DB_TYPE || 'sqlite';
const sqlitePath = process.env.DB_SQLITE_PATH || './data/database.sqlite';

// Guard: отказ на дефолтном dev-SQLite
if (dbType === 'sqlite' && sqlitePath === './data/database.sqlite') {
  console.error(
    '❌ db:recreate отказано: дефолтный dev-SQLite (./data/database.sqlite).\n' +
      'Укажите DB_SQLITE_PATH (или DB_TYPE=postgres) явно для recreate.',
  );
  process.exit(1);
}

const dataSource = new DataSource(
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
        migrations: [__dirname + '/../migrations/*.{ts,js}'],
        logging: process.env.DB_LOGGING === 'true',
      }
    : {
        type: 'sqlite' as const,
        database: sqlitePath,
        entities: ENTITIES,
        synchronize: false,
        migrationsRun: false,
        migrations: [__dirname + '/../migrations/*.{ts,js}'],
        logging: process.env.DB_LOGGING === 'true',
      },
);

async function recreateDatabase() {
  await dataSource.initialize();
  console.log('Connected to database.');

  if (dbType === 'postgres') {
    // DROP TABLE с CASCADE для PostgreSQL
    await dataSource.query('DROP TABLE IF EXISTS "user" CASCADE');
  } else {
    // SQLite не поддерживает CASCADE
    await dataSource.query('DROP TABLE IF EXISTS "user"');
  }
  console.log('Schema dropped.');

  // Накат миграций с нуля
  const migrations = await dataSource.runMigrations();
  console.log(`Applied ${migrations.length} migration(s):`);
  for (const m of migrations) {
    console.log(`  - ${m.name}`);
  }

  await dataSource.destroy();
  console.log('Database recreate complete.');
  process.exit(0);
}

recreateDatabase().catch((err) => {
  console.error('Failed to recreate database:', err);
  process.exit(1);
});