import { IsOptional, IsString, IsInt, Min, IsIn } from 'class-validator';

/** Параметры запроса presigned GET-URL для скачивания. */
export class PresignedDownloadQueryDto {
  @IsString()
  fileKey: string;

  @IsOptional()
  @IsIn(['inline', 'attachment'])
  disposition?: 'inline' | 'attachment';

  @IsOptional()
  @IsInt()
  @Min(1)
  expiresIn?: number;

  @IsOptional()
  @IsString()
  filename?: string;
}