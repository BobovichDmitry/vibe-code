import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Baseline-миграция: создаёт всю схему каркаса одной миграцией.
 * Диалект-агностик — ветвление по типу соединения:
 *   - postgres: SERIAL / TIMESTAMP / now() (как генерирует TypeORM для @CreateDateColumn)
 *   - sqlite:   AUTOINCREMENT / datetime / CURRENT_TIMESTAMP
 *
 * Таблица `user` — авторизация и управление пользователями.
 */
export class InitSchema1740613433000 implements MigrationInterface {
  name = 'InitSchema1740613433000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const isSqlite = queryRunner.connection.options.type === 'sqlite';

    if (isSqlite) {
      await queryRunner.query(`
        CREATE TABLE "user" (
          "id" integer PRIMARY KEY AUTOINCREMENT,
          "login" varchar NOT NULL UNIQUE,
          "passwordHash" varchar NOT NULL,
          "role" varchar NOT NULL DEFAULT 'user',
          "createdAt" datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
    } else {
      await queryRunner.query(`
        CREATE TABLE "user" (
          "id" SERIAL NOT NULL,
          "login" character varying NOT NULL,
          "passwordHash" character varying NOT NULL,
          "role" character varying NOT NULL DEFAULT 'user',
          "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
          CONSTRAINT "UQ_user_login" UNIQUE ("login"),
          CONSTRAINT "PK_user_id" PRIMARY KEY ("id")
        )
      `);
    }
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('user');
  }
}