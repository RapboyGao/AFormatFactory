<template>
  <v-container fluid class="pa-6">
    <v-row>
      <v-col cols="12" md="9">
        <v-card rounded="xl">
          <v-toolbar color="transparent" density="comfortable">
            <v-toolbar-title>任务队列</v-toolbar-title>
            <v-spacer />
            <v-btn variant="tonal" color="primary" @click="queue.startQueue">开始队列</v-btn>
            <v-btn variant="tonal" color="warning" class="ml-2" @click="queue.clearCompleted">清理已完成</v-btn>
            <v-btn variant="tonal" color="error" class="ml-2" :disabled="!selectedIds.length" @click="deleteSelected">删除选中</v-btn>
            <v-btn variant="tonal" color="warning" class="ml-2" :disabled="!selectedIds.length" @click="cancelSelected">终止选中</v-btn>
          </v-toolbar>

          <v-list lines="two" class="pa-2">
            <v-list-item
              v-for="(task, index) in queue.tasks"
              :key="task.id"
              :class="['rounded-lg mb-2', selectedIds.includes(task.id) ? 'bg-blue-grey-darken-4' : '']"
              draggable="true"
              @dragstart="onDragStart(task.id)"
              @dragover.prevent
              @drop="onDrop(task.id)"
              @click="onTaskClick($event, task.id, index)"
            >
              <template #prepend>
                <v-checkbox-btn :model-value="selectedIds.includes(task.id)" @click.stop="toggleSelect(task.id, index, $event as MouseEvent)" />
              </template>

              <v-list-item-title class="text-body-2">{{ task.input }}</v-list-item-title>
              <v-list-item-subtitle>
                <div class="mb-1">输出: {{ task.output }}</div>
                <div class="d-flex align-center ga-2" style="min-width: 260px">
                  <v-progress-linear :model-value="progressPercent(task)" height="8" rounded color="primary" />
                  <span>{{ progressPercent(task) }}%</span>
                </div>
                <div class="text-caption text-medium-emphasis mt-1">
                  帧: {{ task.progress.processed_frames || 0 }} |
                  时长: {{ formatTime(task.progress.processed_time_seconds || 0) }} |
                  速度: {{ formatSpeed(task.progress.speed || 0) }} |
                  码率: {{ formatBitrate(task.progress.bitrate_kbps || 0) }} |
                  FPS: {{ formatFps(task.progress.processed_frames || 0, task.progress.processed_time_seconds || 0) }}
                </div>
              </v-list-item-subtitle>

              <template #append>
                <div class="d-flex align-center ga-2">
                  <v-chip size="small" :color="statusColor(task.status)">{{ task.status }}</v-chip>
                  <v-btn size="small" icon="mdi-stop-circle-outline" color="warning" variant="text" @click.stop="queue.cancelTask(task.id)" />
                  <v-btn size="small" icon="mdi-delete-outline" color="error" variant="text" @click.stop="queue.deleteTask(task.id)" />
                </div>
              </template>
            </v-list-item>
          </v-list>
        </v-card>
      </v-col>

      <v-col cols="12" md="3">
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
            :max="64"
            step="1"
            thumb-label
            label="并发"
            @update:model-value="onConcurrency"
          />
          <div class="text-caption text-medium-emphasis mt-2">支持拖拽排序，Shift 多选。</div>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const selectedIds = ref<string[]>([]);
const lastSelectedIndex = ref<number | null>(null);
const draggingId = ref<string>('');

onMounted(() => void queue.bootstrap());

const progressPercent = (task: { progress: { estimated_ratio: number } }): number => {
  return Math.round((task.progress.estimated_ratio || 0) * 100);
};

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

const selectRange = (from: number, to: number): void => {
  const [start, end] = from <= to ? [from, to] : [to, from];
  const ids = queue.tasks.slice(start, end + 1).map((x) => x.id);
  selectedIds.value = Array.from(new Set([...selectedIds.value, ...ids]));
};

const onTaskClick = (event: MouseEvent | KeyboardEvent, id: string, index: number): void => {
  if (event.shiftKey && lastSelectedIndex.value !== null) {
    selectRange(lastSelectedIndex.value, index);
  } else if (event.metaKey || event.ctrlKey) {
    if (selectedIds.value.includes(id)) selectedIds.value = selectedIds.value.filter((x) => x !== id);
    else selectedIds.value.push(id);
    lastSelectedIndex.value = index;
  } else {
    selectedIds.value = [id];
    lastSelectedIndex.value = index;
  }
};

const toggleSelect = (id: string, index: number, event: MouseEvent | KeyboardEvent): void => {
  onTaskClick(event, id, index);
};

const onDragStart = (id: string): void => {
  draggingId.value = id;
};

const onDrop = async (targetId: string): Promise<void> => {
  const sourceId = draggingId.value;
  draggingId.value = '';
  if (!sourceId || sourceId === targetId) return;

  const ids = queue.tasks.map((x) => x.id);
  const sourceIndex = ids.indexOf(sourceId);
  const targetIndex = ids.indexOf(targetId);
  if (sourceIndex < 0 || targetIndex < 0) return;

  ids.splice(sourceIndex, 1);
  ids.splice(targetIndex, 0, sourceId);
  await queue.reorderTasks(ids);
};

const deleteSelected = async (): Promise<void> => {
  for (const id of [...selectedIds.value]) await queue.deleteTask(id);
  selectedIds.value = [];
};

const cancelSelected = async (): Promise<void> => {
  for (const id of selectedIds.value) await queue.cancelTask(id);
};
</script>
