<template>
  <v-container fluid class="pa-6">
    <v-card class="pa-4" rounded="xl">
      <v-card-title class="text-h6">媒体编辑（单文件）</v-card-title>
      <v-card-text>
        <v-text-field v-model="input" label="输入视频" variant="outlined" />
        <v-text-field v-model="output" label="输出视频" variant="outlined" class="mt-2" />
        <v-text-field v-model="audio" label="附加音频（可选）" variant="outlined" class="mt-2" />
        <v-text-field v-model="subtitle" label="附加字幕（可选）" variant="outlined" class="mt-2" />
        <v-text-field v-model="subtitleCodec" label="字幕编码（默认 mov_text）" variant="outlined" class="mt-2" />
        <v-textarea v-model="metadataRaw" label="Metadata（每行 key=value）" variant="outlined" rows="6" class="mt-2" />
        <v-switch v-model="overwrite" label="覆盖输出" color="primary" inset class="mt-2" />
        <v-btn color="primary" class="mt-2" @click="run">执行媒体编辑</v-btn>
      </v-card-text>
    </v-card>
  </v-container>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { api } from '@/types/api';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const input = ref('');
const output = ref('');
const audio = ref('');
const subtitle = ref('');
const subtitleCodec = ref('mov_text');
const overwrite = ref(true);
const metadataRaw = ref('title=New Title\nartist=Unknown');

const run = async (): Promise<void> => {
  const metadata: Record<string, string> = {};
  for (const line of metadataRaw.value.split('\n')) {
    const i = line.indexOf('=');
    if (i > 0) {
      metadata[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
  }

  await api.runMediaEdit({
    input: input.value,
    output: output.value,
    overwrite: overwrite.value,
    metadata,
    chapters: [],
    additional_audio_input: audio.value || undefined,
    subtitle_input: subtitle.value || undefined,
    subtitle_codec: subtitleCodec.value || undefined
  });
  queue.pushLog('媒体编辑任务完成');
};
</script>
