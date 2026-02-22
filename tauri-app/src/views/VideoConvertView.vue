<template>
  <v-container fluid class="pa-6">
    <v-card class="pa-4" rounded="xl">
      <v-card-title class="text-h6">视频格式转换</v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="12" md="5">
            <v-text-field v-model="inputPaths" label="输入文件（每行一个绝对路径）" variant="outlined" rows="9" textarea />
          </v-col>
          <v-col cols="12" md="5">
            <v-text-field v-model="outputDir" label="输出目录" variant="outlined" />
            <v-select v-model="format" :items="videoFormats" label="输出格式" variant="outlined" class="mt-2" />
            <v-switch v-model="overwrite" label="覆盖同名文件" color="primary" inset />
            <v-textarea v-model="extraArgs" label="高级参数（每个参数空格分隔）" variant="outlined" rows="6" />
          </v-col>
          <v-col cols="12" md="2" class="d-flex align-end">
            <v-btn block color="primary" @click="submit">添加任务</v-btn>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
  </v-container>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const inputPaths = ref('');
const outputDir = ref('');
const format = ref('mp4');
const overwrite = ref(true);
const extraArgs = ref('-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k');
const videoFormats = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'flv', 'm4v', 'ts', 'mpeg', 'ogv', '3gp', 'gif'];

const submit = async (): Promise<void> => {
  const files = inputPaths.value.split('\n').map((x) => x.trim()).filter(Boolean);
  if (!files.length || !outputDir.value.trim()) {
    queue.pushLog('请填写输入文件和输出目录');
    return;
  }
  const args = extraArgs.value.trim() ? extraArgs.value.trim().split(/\s+/g) : [];
  await queue.addTasks(
    files.map((input) => ({
      domain: 'video' as const,
      input,
      output: `${outputDir.value.replace(/\/$/, '')}/${input.split('/').pop()?.replace(/\.[^.]+$/, '')}.${format.value}`,
      format: format.value,
      overwrite: overwrite.value,
      args
    }))
  );
  inputPaths.value = '';
};
</script>
