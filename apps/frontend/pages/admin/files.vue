<script setup lang="ts">
import { useApi } from '~/composables/useApi';

definePageMeta({
  layout: 'admin',
  middleware: ['auth'],
});

interface FileItem {
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
interface ListFilesResponse { items: FileItem[]; total: number; }

const api = useApi();

const items = ref<FileItem[]>([]);
const total = ref(0);
const loading = ref(true);
const error = ref<string | null>(null);

const search = ref('');
const page = ref(0);
const pageSize = ref(20);
let searchTimer: ReturnType<typeof setTimeout> | null = null;

const totalPages = () => Math.max(1, Math.ceil(total.value / pageSize.value));

const loadFiles = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await api.request<ListFilesResponse>('/files', {
      params: {
        search: search.value.trim() || undefined,
        limit: pageSize.value,
        offset: page.value * pageSize.value,
      },
    });
    items.value = res.items;
    total.value = res.total;
  } catch (e: any) {
    error.value = 'Не удалось загрузить список файлов';
    console.error(e);
  } finally {
    loading.value = false;
  }
};

const onSearchInput = () => {
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    page.value = 0;
    loadFiles();
  }, 350);
};

const goToPage = (p: number) => {
  if (p < 0 || p >= totalPages()) return;
  page.value = p;
  loadFiles();
};

const formatSize = (size: string | null): string => {
  if (!size) return '—';
  const n = Number(size);
  if (!Number.isFinite(n)) return size;
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
};

const formatDate = (iso: string): string => {
  try { return new Date(iso).toLocaleString('ru-RU'); } catch { return iso; }
};

const deletingKey = ref<string | null>(null);

const handleDelete = async (file: FileItem) => {
  if (!confirm(`Удалить файл «${file.fileKey}»? Объект в S3 и запись будут удалены.`)) return;
  deletingKey.value = file.fileKey;
  try {
    await api.request('/files', { method: 'DELETE', params: { fileKey: file.fileKey } });
    await loadFiles();
  } catch (e: any) {
    error.value = e?.data?.message || 'Ошибка удаления файла';
    console.error(e);
  } finally {
    deletingKey.value = null;
  }
};

const downloadingKey = ref<string | null>(null);

const uploading = ref(false);
const uploadProgress = ref(0);
const uploadError = ref<string | null>(null);
const uploadResult = ref<{ fileKey: string; fileId: number } | null>(null);
const fileInput = ref<HTMLInputElement | null>(null);
const selectedFile = ref<File | null>(null);
const isDragOver = ref(false);

const onFilePicked = (e: Event) => {
  const target = e.target as HTMLInputElement;
  selectedFile.value = target.files?.[0] ?? null;
  uploadError.value = null;
  uploadResult.value = null;
};

const onDrop = (e: DragEvent) => {
  isDragOver.value = false;
  const file = e.dataTransfer?.files?.[0];
  if (file) {
    selectedFile.value = file;
    uploadError.value = null;
    uploadResult.value = null;
    if (fileInput.value) {
      const dt = new DataTransfer();
      dt.items.add(file);
      fileInput.value.files = dt.files;
    }
  }
};

const handleUpload = async () => {
  if (!selectedFile.value) { uploadError.value = 'Выберите файл'; return; }
  uploading.value = true;
  uploadProgress.value = 0;
  uploadError.value = null;
  uploadResult.value = null;
  try {
    const form = new FormData();
    form.append('file', selectedFile.value);
    const res = await api.request<{ fileKey: string; fileId: number }>('/files', {
      method: 'POST',
      body: form,
      onRequest: (ctx: any) => {
        // Прогресс-загрузка — ofetch поддерживает onRequest, но не onUploadProgress.
        // Прогресс-bar здесь опционален; оставляем заглушку 0→100 по завершению.
        ctx.options.headers = { ...(ctx.options.headers || {}) };
      },
    });
    uploadProgress.value = 100;
    uploadResult.value = res;
    selectedFile.value = null;
    if (fileInput.value) fileInput.value.value = '';
    await loadFiles();
  } catch (e: any) {
    uploadError.value = e?.data?.message || 'Ошибка загрузки файла';
    console.error(e);
  } finally {
    uploading.value = false;
  }
};

const handleDownload = async (file: FileItem) => {
  downloadingKey.value = file.fileKey;
  try {
    const data = await api.request<{ url: string }>('/files/presigned-url', {
      params: { fileKey: file.fileKey, disposition: 'attachment' },
    });
    if (import.meta.client) window.open(data.url, '_blank', 'noopener');
  } catch (e: any) {
    error.value = e?.data?.message || 'Не удалось получить ссылку';
    console.error(e);
  } finally {
    downloadingKey.value = null;
  }
};

// Первичная загрузка (SSR + клиент) — данные в HTML с сервера.
const { data: filesData, pending } = await useAsyncData<ListFilesResponse>(
  'admin-files',
  () => api.request<ListFilesResponse>('/files', {
    params: { limit: pageSize.value, offset: 0 },
  }),
);
watchEffect(() => {
  if (filesData.value) {
    items.value = filesData.value.items;
    total.value = filesData.value.total;
  }
});
// watch регистрируется ПОСЛЕ await — к этому моменту pending уже false,
// поэтому берём текущее значение и включаем immediate для последующих refresh.
loading.value = pending.value;
watch(pending, (p) => { loading.value = p; }, { immediate: true });

watch(pageSize, () => {
  page.value = 0;
  loadFiles();
});
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-2xl font-semibold tracking-tight text-slate-950 dark:text-white">Файлы</h2>
      <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">Управление файлами в S3</p>
    </div>

    <div class="surface-card p-5">
      <h3 class="text-sm font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">Загрузить файл (рандомное имя)</h3>
      <div
        class="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center"
        @dragover.prevent="isDragOver = true"
        @dragleave.prevent="isDragOver = false"
        @drop.prevent="onDrop"
      >
        <label
          class="flex flex-1 cursor-pointer items-center gap-3 rounded-xl border-2 border-dashed px-4 py-4 transition"
          :class="isDragOver ? 'border-brand-500 bg-brand-50 dark:bg-brand-950/30' : 'border-slate-300 hover:border-brand-400 dark:border-slate-700 dark:hover:border-brand-500'"
        >
          <svg class="h-6 w-6 shrink-0 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 7.5m0 0L7.5 12M12 7.5v9" />
          </svg>
          <span class="text-sm text-slate-600 dark:text-slate-300">
            <span v-if="selectedFile" class="font-medium text-slate-900 dark:text-white">{{ selectedFile.name }}</span>
            <span v-else>Перетащите файл сюда или нажмите для выбора…</span>
          </span>
          <input ref="fileInput" type="file" class="hidden" @change="onFilePicked" />
        </label>
        <button @click="handleUpload" :disabled="uploading || !selectedFile" class="btn-primary shrink-0 disabled:opacity-50">
          <span v-if="uploading" class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white"></span>
          {{ uploading ? 'Загрузка…' : 'Загрузить' }}
        </button>
      </div>

      <div v-if="uploading && uploadProgress > 0" class="mt-3">
        <div class="h-2 w-full overflow-hidden rounded-full bg-slate-200 dark:bg-slate-800">
          <div class="h-full rounded-full bg-brand-600 transition-all" :style="{ width: uploadProgress + '%' }"></div>
        </div>
        <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">{{ uploadProgress }}%</p>
      </div>

      <div v-if="uploadResult" class="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm text-emerald-800 dark:border-emerald-900/50 dark:bg-emerald-950/40 dark:text-emerald-200">
        ✅ Загружено: <code class="font-mono">{{ uploadResult.fileKey }}</code> (id #{{ uploadResult.fileId }})
      </div>
      <div v-if="uploadError" class="mt-3 rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/40 dark:text-red-200">{{ uploadError }}</div>
    </div>

    <div class="surface-card flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex flex-1 items-center gap-2">
        <div class="relative flex-1 max-w-md">
          <svg class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-4.3-4.3M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z" />
          </svg>
          <input v-model="search" @input="onSearchInput" type="text" class="input-base pl-9" placeholder="Фильтр по fileKey (подстрока)…" />
        </div>
        <button v-if="search" @click="search = ''; page = 0; loadFiles()" class="text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200">Сбросить</button>
      </div>
      <div class="flex items-center gap-2 text-sm text-slate-500 dark:text-slate-400">
        <span>Всего:</span>
        <span class="font-medium text-slate-700 dark:text-slate-200">{{ total }}</span>
      </div>
    </div>

    <div v-if="error" class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/40 dark:text-red-200">{{ error }}</div>

    <div v-if="loading" class="surface-card flex min-h-[200px] items-center justify-center">
      <div class="h-10 w-10 animate-spin rounded-full border-b-2 border-brand-600"></div>
    </div>

    <div v-else class="surface-card overflow-hidden">
      <div class="overflow-x-auto">
        <table v-if="items.length > 0" class="w-full">
          <thead>
            <tr class="border-b border-slate-200 bg-slate-50/80 dark:border-slate-800 dark:bg-slate-900/50">
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">ID</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">fileKey</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Имя</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Тип</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Размер</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Статус</th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Создан</th>
              <th class="px-4 py-3 text-right text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">Действия</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-200 dark:divide-slate-800">
            <tr v-for="file in items" :key="file.id" class="transition hover:bg-slate-50 dark:hover:bg-slate-900/60">
              <td class="whitespace-nowrap px-4 py-3 text-sm text-slate-500 dark:text-slate-400">#{{ file.id }}</td>
              <td class="px-4 py-3 text-sm font-mono text-slate-900 dark:text-white">
                <span class="break-all">{{ file.fileKey }}</span>
              </td>
              <td class="px-4 py-3 text-sm text-slate-600 dark:text-slate-300">
                <span v-if="file.originalName" class="break-all">{{ file.originalName }}</span>
                <span v-else class="text-slate-400 dark:text-slate-500">—</span>
              </td>
              <td class="px-4 py-3 text-sm text-slate-600 dark:text-slate-300">
                <span v-if="file.contentType" class="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700 dark:bg-slate-800 dark:text-slate-300">{{ file.contentType }}</span>
                <span v-else class="text-slate-400 dark:text-slate-500">—</span>
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-sm text-slate-600 dark:text-slate-300">{{ formatSize(file.size) }}</td>
              <td class="whitespace-nowrap px-4 py-3 text-sm">
                <span class="rounded-full px-2.5 py-1 text-xs font-medium" :class="file.inStorage ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-200' : 'bg-amber-100 text-amber-800 dark:bg-amber-950/40 dark:text-amber-200'">
                  {{ file.inStorage ? 'в хранилище' : 'ожидает' }}
                </span>
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-sm text-slate-500 dark:text-slate-400">{{ formatDate(file.createdAt) }}</td>
              <td class="whitespace-nowrap px-4 py-3 text-right text-sm space-x-3">
                <button @click="handleDownload(file)" :disabled="downloadingKey === file.fileKey || !file.inStorage" class="text-blue-600 hover:text-blue-800 disabled:opacity-50 dark:text-blue-400 dark:hover:text-blue-300" :title="!file.inStorage ? 'Файл ещё не залит в хранилище' : 'Скачать'">
                  <span v-if="downloadingKey === file.fileKey" class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-blue-300 border-t-blue-600"></span>
                  <span v-else>Скачать</span>
                </button>
                <button @click="handleDelete(file)" :disabled="deletingKey === file.fileKey" class="text-red-600 hover:text-red-800 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300">
                  <span v-if="deletingKey === file.fileKey" class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-red-300 border-t-red-600"></span>
                  <span v-else>Удалить</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-else class="flex flex-col items-center justify-center px-6 py-12 text-center">
          <p class="text-sm text-slate-500 dark:text-slate-400">
            {{ search ? 'Файлов не найдено по фильтру.' : 'Файлов пока нет.' }}
          </p>
        </div>
      </div>

      <div v-if="total > pageSize" class="flex items-center justify-between border-t border-slate-200 px-4 py-3 dark:border-slate-800">
        <div class="text-sm text-slate-500 dark:text-slate-400">Страница {{ page + 1 }} из {{ totalPages() }}</div>
        <div class="flex items-center gap-2">
          <button @click="goToPage(0)" :disabled="page === 0" class="btn-secondary px-2 py-1 text-xs disabled:opacity-50">⏮</button>
          <button @click="goToPage(page - 1)" :disabled="page === 0" class="btn-secondary px-3 py-1 text-xs disabled:opacity-50">Назад</button>
          <button @click="goToPage(page + 1)" :disabled="page + 1 >= totalPages()" class="btn-secondary px-3 py-1 text-xs disabled:opacity-50">Далее</button>
          <button @click="goToPage(totalPages() - 1)" :disabled="page + 1 >= totalPages()" class="btn-secondary px-2 py-1 text-xs disabled:opacity-50">⏭</button>
        </div>
      </div>
    </div>
  </div>
</template>