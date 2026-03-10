<template>
  <v-container fluid class="pa-6">
    <v-row>
      <v-col cols="12" md="8">
        <v-card rounded="xl">
          <v-toolbar color="transparent" density="comfortable">
            <v-toolbar-title>任务队列</v-toolbar-title>
            <v-spacer />
            <v-btn variant="tonal" color="primary" @click="queue.startQueue">开始队列</v-btn>
            <v-btn variant="tonal" color="warning" class="ml-2" @click="queue.clearCompleted">清理已完成</v-btn>
          </v-toolbar>

          <v-data-table :headers="headers" :items="queue.tasks" item-value="id" density="comfortable">
            <template #item.progress="{ item }">
              <div class="d-flex flex-column ga-1" style="min-width: 260px">
                <div class="d-flex align-center ga-2">
                  <v-progress-linear :model-value="Math.round((item.progress.estimated_ratio || 0) * 100)" height="8" rounded color="primary" />
                  <span>{{ Math.round((item.progress.estimated_ratio || 0) * 100) }}%</span>
                </div>
                <div class="text-caption text-medium-emphasis">
                  帧: {{ item.progress.processed_frames || 0 }} |
                  时长: {{ formatTime(item.progress.processed_time_seconds || 0) }} |
                  速度: {{ formatSpeed(item.progress.speed || 0) }} |
                  码率: {{ formatBitrate(item.progress.bitrate_kbps || 0) }} |
                  FPS: {{ formatFps(item.progress.processed_frames || 0, item.progress.processed_time_seconds || 0) }}
                </div>
              </div>
            </template>
            <template #item.status="{ item }">
              <v-chip size="small" :color="statusColor(item.status)">{{ item.status }}</v-chip>
            </template>
            <template #item.actions="{ item }">
              <v-btn size="small" icon="mdi-stop-circle-outline" color="warning" variant="text" @click="queue.cancelTask(item.id)" />
              <v-btn size="small" icon="mdi-delete-outline" color="error" variant="text" @click="queue.deleteTask(item.id)" />
            </template>
          </v-data-table>
        </v-card>
      </v-col>

      <v-col cols="12" md="4">
        <v-card rounded="xl" class="pa-4">
          <div class="text-subtitle-1 mb-3">队列统计</div>
          <v-list density="compact">
            <v-list-item title="总任务" :subtitle="String(queue.stats.total)" />
            <v-list-item title="排队" :subtitle="String(queue.stats.queued)" />
            <v-list-item title="运行" :subtitle="String(queue.stats.running)" />
            <v-list-item title="成功" :subtitle="String(queue.stats.success)" />
            <v-list-item title="失败" :subtitle="String(queue.stats.failed)" />
          </v-list>
          <v-slider
            :model-value="queue.concurrency"
            :min="1"
            :max="32"
            step="1"
            thumb-label
            label="并发"
            @update:model-value="onConcurrency"
          />
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const headers = [
  { title: '状态', key: 'status' },
  { title: '输入', key: 'input' },
  { title: '输出', key: 'output' },
  { title: '处理状态', key: 'progress', sortable: false },
  { title: '操作', key: 'actions', sortable: false }
];

onMounted(() => void queue.bootstrap());

const statusColor = (status: string): string => {
  if (status === 'running') return 'primary';
  if (status === 'success') return 'success';
  if (status === 'failed') return 'error';
  if (status === 'cancelled') return 'warning';
  return 'secondary';
};

const onConcurrency = async (value: number): Promise<void> => {
  await queue.applyConcurrency(value);
};

const formatTime = (sec: number): string => {
  if (!Number.isFinite(sec) || sec <= 0) return '0.0s';
  if (sec < 60) return `${sec.toFixed(1)}s`;
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  return `${m}m${s.toFixed(1)}s`;
};

const formatSpeed = (speed: number): string => {
  if (!Number.isFinite(speed) || speed <= 0) return 'N/A';
  return `${speed.toFixed(2)}x`;
};

const formatBitrate = (kbps: number): string => {
  if (!Number.isFinite(kbps) || kbps <= 0) return 'N/A';
  return `${kbps.toFixed(1)}kbps`;
};

const formatFps = (frames: number, sec: number): string => {
  if (!Number.isFinite(frames) || !Number.isFinite(sec) || frames <= 0 || sec <= 0) return 'N/A';
  return (frames / sec).toFixed(1);
};
</script>
