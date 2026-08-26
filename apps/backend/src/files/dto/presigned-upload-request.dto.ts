import { IsOptional, IsString, IsInt, Min, Max } from 'class-validator';

/** Запрос presigned PUT-URL для прямой заливки файла клиентом в S3. */
export class PresignedUploadRequestDto {
  /** Исходное имя файла — используется для генерации ключа и определения расширения. */
  @IsOptional()
  @IsString()
  originalFileName?: string;

  /** MIME-тип, который клиент будет использовать в PUT. */
  @IsOptional()
  @IsString()
  contentType?: string;

  /** Явный ключ объекта. Если не задан — генерируется рандомный. */
  @IsOptional()
  @IsString()
  fileKey?: string;

  /** Срок действия URL в секундах (1..3600). По умолчанию S3_UPLOAD_EXPIRES. */
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(3600)
  expiresIn?: number;
}