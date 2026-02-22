<template>
  <v-container fluid class="pa-6">
    <v-card class="pa-4" rounded="xl">
      <v-card-title class="text-h6">音频格式转换</v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="12" md="5">
            <v-text-field v-model="inputPaths" label="输入文件（每行一个绝对路径）" variant="outlined" rows="9" textarea />
          </v-col>
          <v-col cols="12" md="5">
            <v-text-field v-model="outputDir" label="输出目录" variant="outlined" />
            <v-select v-model="format" :items="audioFormats" label="输出格式" variant="outlined" class="mt-2" />
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
const format = ref('m4a');
const overwrite = ref(true);
const extraArgs = ref('-vn -c:a aac -b:a 192k -ar 44100 -ac 2');
const audioFormats = ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'aiff', 'wma', 'alac'];

const submit = async (): Promise<void> => {
  const files = inputPaths.value.split('\n').map((x) => x.trim()).filter(Boolean);
  if (!files.length || !outputDir.value.trim()) {
    queue.pushLog('请填写输入文件和输出目录');
    return;
  }
  const args = extraArgs.value.trim() ? extraArgs.value.trim().split(/\s+/g) : [];
  await queue.addTasks(
    files.map((input) => ({
      domain: 'audio' as const,
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
