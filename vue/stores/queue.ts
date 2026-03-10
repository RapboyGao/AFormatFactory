import { defineStore } from 'pinia';
import { api } from '@/types/api';
import type { ConversionTaskDraft, QueueTask } from '@/types/models';

export const useQueueStore = defineStore('queue', {
  state: () => ({
    tasks: [] as QueueTask[],
    appLogs: [] as string[],
    capabilities: { muxers: [] as string[], encoders: [] as string[] },
    concurrency: 1,
    polling: false
  }),
  getters: {
    stats: (state) => ({
      total: state.tasks.length,
      queued: state.tasks.filter((t) => t.status === 'queued').length,
      running: state.tasks.filter((t) => t.status === 'running').length,
      success: state.tasks.filter((t) => t.status === 'success').length,
      failed: state.tasks.filter((t) => t.status === 'failed').length
    })
  },
  actions: {
    pushLog(message: string): void {
      const line = `[${new Date().toLocaleTimeString()}] ${message}`;
      this.appLogs.unshift(line);
      this.appLogs = this.appLogs.slice(0, 500);
    },
    async bootstrap(): Promise<void> {
      this.capabilities = await api.detectCapabilities();
      this.concurrency = await api.getConcurrency();
      await this.refreshTasks();
      if (!this.polling) {
        this.polling = true;
        setInterval(() => void this.refreshTasks(), 500);
      }
    },
    async refreshTasks(): Promise<void> {
      this.tasks = await api.listTasks();
    },
    async addTasks(drafts: ConversionTaskDraft[]): Promise<void> {
      const count = await api.createTasks(drafts);
      this.pushLog(`已创建 ${count} 个任务`);
      await this.refreshTasks();
    },
    async startQueue(): Promise<void> {
      await api.startQueue();
      this.pushLog('已启动任务队列');
    },
    async clearCompleted(): Promise<void> {
      await api.clearCompleted();
      this.pushLog('已清理已完成任务');
      await this.refreshTasks();
    },
    async cancelTask(id: string): Promise<void> {
      await api.cancelTask(id);
      this.pushLog(`已请求终止任务 ${id}`);
    },
    async deleteTask(id: string): Promise<void> {
      await api.deleteTask(id);
      await this.refreshTasks();
    },
    async reorderTasks(orderedIds: string[]): Promise<void> {
      await api.reorderTasks(orderedIds);
      await this.refreshTasks();
    },
    async applyConcurrency(value: number): Promise<void> {
      await api.setConcurrency(value);
      this.concurrency = value;
    }
  }
});
