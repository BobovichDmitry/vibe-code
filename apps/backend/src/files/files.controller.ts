import {
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Post,
  Query,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
  Logger,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response, Request as ExpressRequest } from 'express';
import { FileService } from './file.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PresignedUploadRequestDto } from './dto/presigned-upload-request.dto';
import { PresignedDownloadQueryDto } from './dto/presigned-download-query.dto';
import { UpdateFileMetaRequestDto } from './dto/update-file-meta-request.dto';
import { ListFilesQueryDto } from './dto/list-files-query.dto';
import { buildContentDisposition } from './file.utils';

/**
 * Контроллер файлов. Префикс `files` → итоговый путь `/api/files/...`.
 *
 * Все эндпоинты под JWT. fileKey передаётся в query (?fileKey=...) для
 * надёжной поддержки ключей со слэшами (напр. `uploads/abc_.png`).
 *
 * Эндпоинты:
 *   POST   /api/files                   multipart `file` → прямая загрузка
 *   POST   /api/files/presigned-upload  JSON   → presigned PUT url
 *   POST   /api/files/update-meta       JSON   → подтянуть size/contentType/inStorage
 *   GET    /api/files/presigned-url?fileKey=&disposition=&expiresIn=&filename=
 *   GET    /api/files/stream?fileKey=...       → стрим (inline)
 *   GET    /api/files/download?fileKey=...     → стрим (attachment)
 *   DELETE /api/files?fileKey=...
 */
@Controller('files')
export class FilesController {
  private readonly logger = new Logger(FilesController.name);

  constructor(private readonly fileService: FileService) {}

  /** Прямая загрузка через multipart. */
  @Post()
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('file'))
  async uploadFile(@UploadedFile() file: Express.Multer.File, @Req() req: ExpressRequest) {
    if (!file) {
      throw new NotFoundException('No file uploaded (field "file" expected)');
    }
    return this.fileService.uploadFileWithRandomName(file.buffer, {
      contentType: file.mimetype,
      originalFileName: file.originalname,
      userId: req.user?.['id'],
    });
  }

  /** Список файлов с фильтром по fileKey и пагинацией. */
  @Get()
  @UseGuards(JwtAuthGuard)
  async listFiles(@Query() query: ListFilesQueryDto) {
    return this.fileService.listFiles({
      search: query.search,
      limit: query.limit,
      offset: query.offset,
    });
  }

  /** Запрос presigned PUT-URL — клиент льёт файл напрямую в S3. */
  @Post('presigned-upload')
  @UseGuards(JwtAuthGuard)
  async presignedUpload(@Req() req: ExpressRequest, @Body() body: PresignedUploadRequestDto) {
    return this.fileService.getPresignedUploadUrl(
      { id: req.user?.['id'] },
      body,
    );
  }

  /** Обновить мета после presigned-загрузки (size/contentType/inStorage=true). */
  @Post('update-meta')
  @UseGuards(JwtAuthGuard)
  async updateMeta(@Body() body: UpdateFileMetaRequestDto) {
    await this.fileService.updateFileMeta(body.fileKey);
    return { ok: true };
  }

  /** Presigned GET-URL для скачивания. */
  @Get('presigned-url')
  @UseGuards(JwtAuthGuard)
  async presignedDownloadUrl(@Query() query: PresignedDownloadQueryDto) {
    if (!query.fileKey) throw new NotFoundException('fileKey is required');
    return this.fileService.getSignedDownloadUrl(query.fileKey, {
      disposition: query.disposition,
      filename: query.filename,
      expiresIn: query.expiresIn,
    });
  }

  /** Стрим файла (inline — браузер показывает). */
  @Get('stream')
  @UseGuards(JwtAuthGuard)
  async streamFile(@Query('fileKey') fileKey: string, @Res() res: Response) {
    if (!fileKey) throw new NotFoundException('fileKey is required');
    await this.pipeFile(fileKey, res, 'inline');
  }

  /** Скачивание файла (attachment — браузер сохраняет). */
  @Get('download')
  @UseGuards(JwtAuthGuard)
  async downloadFile(@Query('fileKey') fileKey: string, @Res() res: Response) {
    if (!fileKey) throw new NotFoundException('fileKey is required');
    await this.pipeFile(fileKey, res, 'attachment');
  }

  /** Удаление файла (объект в S3 + запись в БД). */
  @Delete()
  @UseGuards(JwtAuthGuard)
  async deleteFile(@Query('fileKey') fileKey: string) {
    if (!fileKey) throw new NotFoundException('fileKey is required');
    return this.fileService.deleteFile(fileKey);
  }

  // ───────────────────────── helpers ─────────────────────────

  private async pipeFile(
    fileKey: string,
    res: Response,
    disposition: 'inline' | 'attachment',
  ): Promise<void> {
    const info = await this.fileService.getFileInfo(fileKey);
    const stream = await this.fileService.getFileStream(fileKey);

    const contentType = info?.contentType || 'application/octet-stream';
    const fileName = info?.originalName || fileKey.split('/').pop() || 'file';

    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Disposition', buildContentDisposition(fileName, disposition));
    if (info?.size) {
      res.setHeader('Content-Length', info.size);
    }

    stream.on('error', (err) => {
      this.logger.error(`stream error for "${fileKey}": ${err.message}`);
      if (!res.headersSent) {
        res.status(404).end();
      } else {
        res.end();
      }
    });
    stream.pipe(res);
  }
}