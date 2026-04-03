import { invoke } from '@tauri-apps/api/core';
import type { ConversionTaskDraft, MediaEditRequest, QueueTask } from './models';

export const api = {
  createTasks: (drafts: ConversionTaskDraft[]) => invoke<number>('create_tasks', { drafts }),
  startQueue: () => invoke<void>('start_queue'),
  cancelTask: (id: string) => invoke<void>('cancel_task', { id }),
  deleteTask: (id: string) => invoke<void>('delete_task', { id }),
  clearCompleted: () => invoke<void>('clear_completed'),
  listTasks: () => invoke<QueueTask[]>('list_tasks'),
  setConcurrency: (value: number) => invoke<void>('set_concurrency', { value }),
  getConcurrency: () => invoke<number>('get_concurrency'),
  pickInputFiles: () => invoke<string[]>('pick_input_files'),
  pickImageFiles: () => invoke<string[]>('pick_image_files'),
  pickOutputDirectory: () => invoke<string | null>('pick_output_directory'),
  exportImageAsJpeg: (inputPath: string) => invoke<string>('export_image_as_jpeg', { inputPath }),
  reorderTasks: (orderedIds: string[]) => invoke<void>('reorder_tasks', { orderedIds }),
  detectCapabilities: () => invoke<{ muxers: string[]; encoders: string[] }>('detect_capabilities'),
  runMediaEdit: (request: MediaEditRequest) => invoke<void>('run_media_edit', { request })
};
