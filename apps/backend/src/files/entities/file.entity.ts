import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * Запись о файле в S3. Создаётся при прямой загрузке и при запросе presigned-URL.
 *
 * `inStorage = false` после presigned-upload (файл ещё не залит) и `true`
 * после прямой загрузки / вызова update-meta (headObject подтвердил наличие).
 */
@Entity('file')
export class FileEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 512, unique: true })
  fileKey: string;

  @Column({ type: 'varchar', nullable: true })
  originalName: string | null;

  @Column({ type: 'varchar', nullable: true })
  size: string | null;

  @Column({ type: 'varchar', nullable: true })
  contentType: string | null;

  @Column({ type: 'boolean', default: false })
  inStorage: boolean;

  @Column({ type: 'integer', nullable: true })
  userId: number | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}