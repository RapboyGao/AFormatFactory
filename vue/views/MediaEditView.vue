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
        <div class="text-subtitle-2 mt-4 mb-2">Chapter 编辑</div>
        <v-row v-for="(chapter, index) in chapters" :key="index" class="align-center">
          <v-col cols="12" md="3"><v-text-field v-model="chapter.start_ms" label="开始(ms)" variant="outlined" density="compact" /></v-col>
          <v-col cols="12" md="3"><v-text-field v-model="chapter.end_ms" label="结束(ms)" variant="outlined" density="compact" /></v-col>
          <v-col cols="12" md="5"><v-text-field v-model="chapter.title" label="标题" variant="outlined" density="compact" /></v-col>
          <v-col cols="12" md="1"><v-btn icon="mdi-delete-outline" color="error" variant="text" @click="removeChapter(index)" /></v-col>
        </v-row>
        <v-btn variant="tonal" size="small" class="mt-1" @click="addChapter">添加 Chapter</v-btn>
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
const chapters = ref<Array<{ start_ms: string; end_ms: string; title: string }>>([]);

const addChapter = (): void => {
  chapters.value.push({ start_ms: '0', end_ms: '10000', title: 'Chapter' });
};

const removeChapter = (index: number): void => {
  chapters.value.splice(index, 1);
};

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
    chapters: chapters.value
      .map((x) => ({
        start_ms: Number(x.start_ms),
        end_ms: Number(x.end_ms),
        title: x.title.trim()
      }))
      .filter((x) => Number.isFinite(x.start_ms) && Number.isFinite(x.end_ms) && x.end_ms > x.start_ms && x.title.length > 0),
    additional_audio_input: audio.value || undefined,
    subtitle_input: subtitle.value || undefined,
    subtitle_codec: subtitleCodec.value || undefined
  });
  queue.pushLog('媒体编辑任务完成');
};
</script>
