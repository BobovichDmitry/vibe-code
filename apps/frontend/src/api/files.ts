import api from './index';

export interface FileItem {
  id: number;
  fileKey: string;
  originalName: string | null;
  size: string | null;
  contentType: string | null;
  inStorage: boolean;
  userId: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface ListFilesResponse {
  items: FileItem[];
  total: number;
}

export const listFiles = async (params: {
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<ListFilesResponse> => {
  const response = await api.get<ListFilesResponse>('/api/files', { params });
  return response.data;
};

export const deleteFile = async (fileKey: string): Promise<void> => {
  await api.delete('/api/files', { params: { fileKey } });
};

export interface UploadFileResult {
  fileKey: string;
  fileId: number;
}

/** Прямая загрузка файла через multipart-поле `file` (рандомное имя на бэке). */
export const uploadFile = async (
  file: File,
  onProgress?: (percent: number) => void,
): Promise<UploadFileResult> => {
  const form = new FormData();
  form.append('file', file);
  const response = await api.post<UploadFileResult>('/api/files', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
    onUploadProgress: (e) => {
      if (onProgress && e.total) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    },
  });
  return response.data;
};

/** Presigned GET-URL для скачивания (открывается в новой вкладке / triggers download). */
export const getFileDownloadUrl = async (
  fileKey: string,
  disposition: 'inline' | 'attachment' = 'attachment',
): Promise<string> => {
  const response = await api.get<{ url: string }>('/api/files/presigned-url', {
    params: { fileKey, disposition },
  });
  return response.data.url;
};