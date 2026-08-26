import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FileEntity } from './entities/file.entity';
import { FileService } from './file.service';
import { FilesController } from './files.controller';
import { S3_CONFIG, loadS3ConfigFromEnv } from './s3.config';

@Module({
  imports: [TypeOrmModule.forFeature([FileEntity])],
  controllers: [FilesController],
  providers: [
    FileService,
    {
      provide: S3_CONFIG,
      useFactory: () => loadS3ConfigFromEnv(),
    },
  ],
  exports: [FileService],
})
export class FilesModule {}