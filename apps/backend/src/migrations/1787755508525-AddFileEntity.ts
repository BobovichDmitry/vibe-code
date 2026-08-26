import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Добавляет таблицу `file` (мета файлов в S3).
 * Диалект-агностик (по образцу InitSchema):
 *   - postgres: SERIAL / TIMESTAMP / now()
 *   - sqlite:   AUTOINCREMENT / datetime / CURRENT_TIMESTAMP
 */
export class AddFileEntity1787755508525 implements MigrationInterface {
  name = 'AddFileEntity1787755508525';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const isSqlite = queryRunner.connection.options.type === 'sqlite';

    if (isSqlite) {
      await queryRunner.query(`
        CREATE TABLE "file" (
          "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          "fileKey" varchar(512) NOT NULL,
          "originalName" varchar,
          "size" varchar,
          "contentType" varchar,
          "inStorage" boolean NOT NULL DEFAULT (0),
          "userId" integer,
          "createdAt" datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT "UQ_file_fileKey" UNIQUE ("fileKey")
        )
      `);
    } else {
      await queryRunner.query(`
        CREATE TABLE "file" (
          "id" SERIAL NOT NULL,
          "fileKey" character varying(512) NOT NULL,
          "originalName" character varying,
          "size" character varying,
          "contentType" character varying,
          "inStorage" boolean NOT NULL DEFAULT false,
          "userId" integer,
          "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
          "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
          CONSTRAINT "UQ_file_fileKey" UNIQUE ("fileKey"),
          CONSTRAINT "PK_file_id" PRIMARY KEY ("id")
        )
      `);
    }
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('file');
  }
}