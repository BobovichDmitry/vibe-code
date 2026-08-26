import {
  ConflictException,
  Inject,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as crypto from 'crypto';
import * as path from 'path';
import { Readable } from 'stream';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  NoSuchKey,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import * as mime from 'mime-types';
import * as detectContentType from 'detect-content-type';
import { FileEntity } from './entities/file.entity';
import { S3_CONFIG, S3Config } from './s3.config';
import { PresignedUploadRequestDto } from './dto/presigned-upload-request.dto';

export interface UploadResult {
  fileKey: string;
  fileId: number;
}

export interface PresignedUploadResult extends UploadResult {
  url: string;
}

export interface SignedDownloadUrlOptions {
  disposition?: 'inline' | 'attachment';
  filename?: string;
  expiresIn?: number;
}

@Injectable()
export class FileService {
  private readonly logger = new Logger(FileService.name);
  private readonly s3: S3Client;
  /** Отдельный клиент для presigned-URL'ов — может указывать на публичный домен. */
  private readonly presignS3: S3Client;

  constructor(
    @Inject(S3_CONFIG) private readonly config: S3Config,
    @InjectRepository(FileEntity) private readonly files: Repository<FileEntity>,
  ) {
    const baseClientConfig = {
      region: config.region,
      credentials: { accessKeyId: config.accessKey, secretAccessKey: config.secretKey },
      forcePathStyle: config.forcePathStyle,
    };
    this.s3 = new S3Client({ ...baseClientConfig, endpoint: config.endpoint });

    // Если публичный URL отличается от внутреннего endpoint — presign через него.
    this.presignS3 =
      config.publicUrl && config.publicUrl !== config.endpoint
        ? new S3Client({ ...baseClientConfig, endpoint: config.publicUrl })
        : this.s3;
  }

  // ───────────────────────────── загрузка ─────────────────────────────

  /** Загрузить буфер с рандомным ключом. */
  async uploadFileWithRandomName(
    fileBuffer: Buffer,
    opts: { contentType?: string; originalFileName?: string; userId?: number | null },
  ): Promise<UploadResult> {
    const ext = this.resolveExtension(opts.originalFileName, opts.contentType);
    const randomPart = `${Date.now().toString(16)}_${crypto.randomBytes(16).toString('hex')}`;
    const suffix = ext ? `.${ext}` : '';
    const key = this.withPrefix(`${randomPart}${suffix}`);

    const contentType =
      opts.contentType ||
      (opts.originalFileName ? (mime.lookup(opts.originalFileName) as string) || undefined : undefined) ||
      (this.tryDetectContentType(fileBuffer) as string) ||
      'application/octet-stream';

    await this.putObject(key, fileBuffer, contentType);
    const entity = await this.files.save(
      this.files.create({
        fileKey: key,
        originalName: opts.originalFileName ?? null,
        contentType,
        inStorage: true,
        userId: opts.userId ?? null,
      }),
    );
    return { fileKey: key, fileId: entity.id };
  }

  /** Загрузить буфер по явному ключу. */
  async uploadFile(
    fileBuffer: Buffer,
    opts: { key: string; contentType?: string; originalFileName?: string; userId?: number | null },
  ): Promise<UploadResult> {
    const key = this.normalizeKey(opts.key);
    const exists = await this.files.count({ where: { fileKey: key } });
    if (exists > 0) {
      throw new ConflictException(`File key "${key}" already exists`);
    }

    const contentType =
      opts.contentType ||
      (opts.originalFileName ? (mime.lookup(opts.originalFileName) as string) || undefined : undefined) ||
      (this.tryDetectContentType(fileBuffer) as string) ||
      'application/octet-stream';

    await this.putObject(key, fileBuffer, contentType);
    const entity = await this.files.save(
      this.files.create({
        fileKey: key,
        originalName: opts.originalFileName ?? null,
        contentType,
        inStorage: true,
        userId: opts.userId ?? null,
      }),
    );
    return { fileKey: key, fileId: entity.id };
  }

  // ───────────────────────── чтение / удаление ─────────────────────────

  /** Стрим объекта из S3. */
  async getFileStream(fileKey: string): Promise<Readable> {
    const key = this.normalizeKey(fileKey);
    try {
      const output = await this.s3.send(
        new GetObjectCommand({ Bucket: this.config.bucket, Key: key }),
      );
      // В v3 Body — Readable | ReadableStream | Blob. В node-окружении это Readable.
      const body = output.Body as Readable;
      if (!body || typeof (body as any).pipe !== 'function') {
        // Подстраховка для web-stream: оборачиваем в Readable.
        return Readable.fromWeb(body as any);
      }
      return body;
    } catch (err: any) {
      if (err.name === 'NoSuchKey' || err.$metadata?.httpStatusCode === 404) {
        throw new NotFoundException(`File "${key}" not found in storage`);
      }
      throw this.mapS3Error(err, `getFileStream(${key})`);
    }
  }

  /** Удалить объект и запись в БД. */
  async deleteFile(fileKey: string): Promise<{ deleted: boolean }> {
    const key = this.normalizeKey(fileKey);
    try {
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.config.bucket, Key: key }));
    } catch (err) {
      throw this.mapS3Error(err, `deleteFile(${key})`);
    }
    await this.files.delete({ fileKey: key });
    this.logger.log(`Deleted file "${key}"`);
    return { deleted: true };
  }

  // ───────────────────────── presigned ─────────────────────────

  /** Presigned GET-URL для скачивания/стрима. */
  async getSignedDownloadUrl(
    fileKey: string,
    opts: SignedDownloadUrlOptions = {},
  ): Promise<{ url: string }> {
    const key = this.normalizeKey(fileKey);
    const entity = await this.files.findOne({ where: { fileKey: key } });
    if (!entity) {
      throw new NotFoundException(`File "${key}" not found`);
    }

    const expiresIn = opts.expiresIn ?? this.config.downloadExpires;
    const command = new GetObjectCommand({
      Bucket: this.config.bucket,
      Key: key,
      ResponseContentDisposition: opts.filename
        ? this.buildDisposition(opts.filename, opts.disposition ?? 'inline')
        : undefined,
      ResponseContentType: entity.contentType ?? undefined,
    });
    const url = await getSignedUrl(this.presignS3, command, { expiresIn });
    return { url };
  }

  /** Presigned PUT-URL + создание записи (inStorage=false). Без пустого объекта-маркера. */
  async getPresignedUploadUrl(
    user: { id: number } | null,
    body: PresignedUploadRequestDto,
  ): Promise<PresignedUploadResult> {
    const ext = this.resolveExtension(body.originalFileName, body.contentType);
    let key = body.fileKey
      ? this.normalizeKey(body.fileKey)
      : this.withPrefix(
          `${Date.now().toString(16)}_${crypto.randomBytes(16).toString('hex')}${ext ? `.${ext}` : ''}`,
        );

    // Уникальность по записи в БД.
    const existing = await this.files.count({ where: { fileKey: key } });
    if (existing > 0) {
      throw new ConflictException(`File key "${key}" already exists`);
    }
    // Уникальность по факту в S3 (headObject не должен найти объект).
    try {
      await this.s3.send(new HeadObjectCommand({ Bucket: this.config.bucket, Key: key }));
      // headObject не кинул → объект существует.
      throw new ConflictException(`File key "${key}" already exists in storage`);
    } catch (err: any) {
      const code = err.name || err.$metadata?.httpStatusCode;
      if (code !== 'NotFound' && code !== 404 && !(err instanceof ConflictException)) {
        throw this.mapS3Error(err, `getPresignedUploadUrl head(${key})`);
      }
      // 404 — ожидаемо, идём дальше.
    }

    const entity = await this.files.save(
      this.files.create({
        fileKey: key,
        originalName: body.originalFileName ?? null,
        contentType: body.contentType ?? null,
        inStorage: false,
        userId: user?.id ?? null,
      }),
    );

    const expiresIn = body.expiresIn ?? this.config.uploadExpires;
    const url = await getSignedUrl(
      this.presignS3,
      new PutObjectCommand({
        Bucket: this.config.bucket,
        Key: key,
        ContentType: body.contentType ?? undefined,
      }),
      { expiresIn },
    );

    this.logger.log(`Generated presigned PUT url for "${key}"`);
    return { url, fileKey: key, fileId: entity.id };
  }

  // ───────────────────────── мета ─────────────────────────

  /** Мета файла из сущности (contentType, originalName, size) — для стрима/скачивания. */
  async getFileInfo(fileKey: string): Promise<FileEntity | null> {
    const key = this.normalizeKey(fileKey);
    return this.files.findOne({ where: { fileKey: key } });
  }

  /** Список файлов с фильтром по fileKey (substring, case-insensitive) и пагинацией. */
  async listFiles(opts: {
    search?: string;
    limit?: number;
    offset?: number;
  }): Promise<{ items: FileEntity[]; total: number }> {
    const limit = Math.min(Math.max(opts.limit ?? 50, 1), 200);
    const offset = Math.max(opts.offset ?? 0, 0);

    const qb = this.files.createQueryBuilder('file').orderBy('file.id', 'DESC');

    if (opts.search) {
      // Подстрока по fileKey (ILIKE в postgres, LIKE в sqlite — оба case-insensitive
      // через LOWER, чтобы поведение совпадало).
      qb.andWhere('LOWER(file.fileKey) LIKE :q', {
        q: `%${opts.search.toLowerCase()}%`,
      });
    }

    const [items, total] = await qb
      .skip(offset)
      .take(limit)
      .getManyAndCount();

    return { items, total };
  }

  /** Подтянуть size/contentType из headObject, проставить inStorage=true. */
  async updateFileMeta(fileKey: string): Promise<void> {
    const key = this.normalizeKey(fileKey);
    const entity = await this.files.findOne({ where: { fileKey: key } });
    if (!entity) {
      throw new NotFoundException(`File "${key}" not found`);
    }
    try {
      const head = await this.s3.send(
        new HeadObjectCommand({ Bucket: this.config.bucket, Key: key }),
      );
      if (head.ContentLength != null) {
        entity.size = String(head.ContentLength);
      }
      if (head.ContentType) {
        entity.contentType = head.ContentType;
      }
      entity.inStorage = true;
      await this.files.save(entity);
    } catch (err: any) {
      const code = err.name || err.$metadata?.httpStatusCode;
      if (code === 'NotFound' || code === 404) {
        throw new NotFoundException(`File "${key}" not found in storage`);
      }
      throw this.mapS3Error(err, `updateFileMeta(${key})`);
    }
  }

  /** Размер объекта: из сущности, иначе через headObject (с сохранением). */
  async getFileSize(fileKey: string): Promise<string | undefined> {
    const key = this.normalizeKey(fileKey);
    const entity = await this.files.findOne({ where: { fileKey: key } });
    if (entity?.size) {
      return entity.size;
    }
    try {
      const head = await this.s3.send(
        new HeadObjectCommand({ Bucket: this.config.bucket, Key: key }),
      );
      const size = head.ContentLength != null ? String(head.ContentLength) : undefined;
      if (entity && size) {
        entity.size = size;
        await this.files.save(entity);
      }
      return size;
    } catch (err: any) {
      const code = err.name || err.$metadata?.httpStatusCode;
      if (code === 'NotFound' || code === 404) {
        return undefined;
      }
      throw this.mapS3Error(err, `getFileSize(${key})`);
    }
  }

  // ───────────────────────── helpers ─────────────────────────

  private resolveExtension(originalFileName?: string, contentType?: string): string {
    if (originalFileName) {
      const ext = path.extname(originalFileName).replace(/^\./, '');
      if (ext) return ext;
    }
    if (contentType) {
      const ext = mime.extension(contentType);
      if (ext) return ext;
    }
    return '';
  }

  private tryDetectContentType(buffer: Buffer): string | undefined {
    try {
      return (detectContentType as any)(buffer) as string | undefined;
    } catch {
      return undefined;
    }
  }

  private normalizeKey(key: string): string {
    return key.startsWith('/') ? key.substring(1) : key;
  }

  private withPrefix(key: string): string {
    return this.config.keyPrefix ? `${this.config.keyPrefix}/${key}` : key;
  }

  private buildDisposition(
    fileName: string,
    disposition: 'inline' | 'attachment',
  ): string {
    const safe = (fileName || 'file')
      .replace(/[\u0000-\u001F\u007F]/g, '')
      .replace(/[\\/]/g, '_')
      .trim() || 'file';
    const ascii = safe
      .normalize('NFKD')
      .replace(/[^\x20-\x7E]/g, '_')
      .replace(/["\\]/g, '_')
      .replace(/\s+/g, ' ')
      .trim() || 'file';
    const utf8 = encodeURIComponent(safe).replace(/['()*]/g, (ch) =>
      `%${ch.charCodeAt(0).toString(16).toUpperCase()}`,
    );
    return `${disposition}; filename="${ascii}"; filename*=UTF-8''${utf8}`;
  }

  private async putObject(key: string, buffer: Buffer, contentType: string): Promise<void> {
    try {
      await this.s3.send(
        new PutObjectCommand({
          Bucket: this.config.bucket,
          Key: key,
          Body: buffer,
          ContentType: contentType,
        }),
      );
    } catch (err) {
      throw this.mapS3Error(err, `putObject(${key})`);
    }
  }

  private mapS3Error(err: any, context: string): Error {
    this.logger.error(`${context} failed: ${err?.name} ${err?.message}`);
    if (err?.name === 'NoSuchKey' || err?.$metadata?.httpStatusCode === 404) {
      return new NotFoundException(`File not found`);
    }
    if (err?.$metadata?.httpStatusCode === 409) {
      return new ConflictException(`Conflict in S3: ${err?.message}`);
    }
    return new InternalServerErrorException(`S3 operation failed: ${err?.message || err}`);
  }
}