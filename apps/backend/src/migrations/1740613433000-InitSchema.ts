import { MigrationInterface, QueryRunner, Table } from 'typeorm';

/**
 * Baseline-миграция: создаёт всю схему каркаса одной миграцией.
 * Диалект-агностик — Table API (без голого SQL-ветвления).
 *
 * Таблица `user` — авторизация и управление пользователями.
 */
export class InitSchema1740613433000 implements MigrationInterface {
  name = 'InitSchema1740613433000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.createTable(
      new Table({
        name: 'user',
        columns: [
          {
            name: 'id',
            type: 'integer',
            isPrimary: true,
            isGenerated: true,
            generationStrategy: 'increment',
          },
          {
            name: 'login',
            type: 'varchar',
            isNullable: false,
            isUnique: true,
          },
          {
            name: 'passwordHash',
            type: 'varchar',
            isNullable: false,
          },
          {
            name: 'role',
            type: 'varchar',
            default: "'user'",
            isNullable: false,
          },
          {
            name: 'createdAt',
            type: 'datetime',
            isNullable: false,
            default: 'CURRENT_TIMESTAMP',
          },
          {
            name: 'updatedAt',
            type: 'datetime',
            isNullable: false,
            default: 'CURRENT_TIMESTAMP',
          },
        ],
      }),
      true,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('user');
  }
}