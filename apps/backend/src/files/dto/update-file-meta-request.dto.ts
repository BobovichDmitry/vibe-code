import { IsString } from 'class-validator';

/** Тело запроса update-meta — подтянуть size/contentType из headObject. */
export class UpdateFileMetaRequestDto {
  @IsString()
  fileKey: string;
}