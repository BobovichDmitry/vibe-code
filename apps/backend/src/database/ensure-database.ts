import { DataSource } from 'typeorm';

/**
 * Автосоздание базы данных при старте backend'а (только postgres).
 *
 * Зачем: POSTGRES_DB в контейнере postgres применяется ТОЛЬКО при первой
 * инициализации тома (пустой /var/lib/postgresql/data). Если том уже был
 * создан с другим именем БД (переименование проекта, старый деплой,
 * ручные эксперименты), backend не сможет подключиться — таблицу pg_database
 * он сам не расширит. Здесь мы до инициализации TypeORM подключаемся к
 * системной базе 'postgres' (создаётся initdb всегда) и создаём DB_DATABASE,
 * если её нет. Дальше TypeORM (migrationsRun) создаёт таблицы сам.
 *
 * Требование: DB_USERNAME должен иметь право CREATEDB. В этом шаблоне
 * POSTGRES_USER создаётся postgres-образом как superuser — права есть.
 *
 * Для DB_TYPE=sqlite — no-op.
 */
export async function ensureDatabaseExists(): Promise<void> {
  if ((process.env.DB_TYPE || 'sqlite') !== 'postgres') {
    return;
  }

  const database = process.env.DB_DATABASE || 'vibe_setup_ui';
  const host = process.env.DB_HOST || 'localhost';
  const port = parseInt(process.env.DB_PORT || '5432', 10);
  const username = process.env.DB_USERNAME || 'postgres';
  const password = process.env.DB_PASSWORD || 'postgres';

  // Идентификатор в кавычках: экранируем встроенные двойные кавычки.
  const quotedName = `"${database.replace(/"/g, '""')}"`;

  // postgres может стартовать позже backend'а (depends_on: service_started)
  // — несколько попыток с паузой, чтобы не ловить рестарты контейнера.
  const maxAttempts = 5;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const maintenance = new DataSource({
      type: 'postgres',
      host,
      port,
      username,
      password,
      database: 'postgres', // системная maintenance-база
      logging: false,
    });
    try {
      await maintenance.initialize();
      const existing = await maintenance.query(
        'SELECT 1 FROM pg_database WHERE datname = $1',
        [database],
      );
      if (existing.length > 0) {
        return; // БД уже есть — ничего не делаем
      }
      console.log(`[db] База "${database}" не существует — создаю...`);
      await maintenance.query(`CREATE DATABASE ${quotedName}`);
      console.log(`[db] База "${database}" создана.`);
      return;
    } catch (err) {
      if (attempt === maxAttempts) {
        throw new Error(
          `[db] Не удалось убедиться в существовании БД "${database}" после ${maxAttempts} попыток: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
      console.warn(
        `[db] Попытка ${attempt}/${maxAttempts}: postgres ещё не готов (${
          err instanceof Error ? err.message : String(err)
        }) — повтор через 3с...`,
      );
      await new Promise((r) => setTimeout(r, 3000));
    } finally {
      if (maintenance.isInitialized) {
        await maintenance.destroy().catch(() => undefined);
      }
    }
  }
}