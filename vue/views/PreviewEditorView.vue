<template>
  <v-container fluid class="pa-4">
    <v-card rounded="xl" class="pa-4">
      <div class="d-flex align-center mb-3">
        <div class="text-h6">预览编辑</div>
        <v-spacer />
        <v-btn variant="tonal" @click="saveEdits">保存预览参数</v-btn>
      </div>

      <v-alert v-if="!file" type="warning" variant="tonal">未指定预览文件。</v-alert>
      <template v-else>
        <div class="text-caption mb-2 text-medium-emphasis">{{ file }}</div>
        <video ref="videoRef" :src="toFileUrl(file)" style="width: 100%; max-height: 520px; background: #000" />
        <v-row class="mt-3">
          <v-col cols="12" md="3"><v-text-field v-model="startTime" label="开始时间(-ss)" variant="outlined" /></v-col>
          <v-col cols="12" md="3"><v-text-field v-model="duration" label="时长(-t)" variant="outlined" /></v-col>
          <v-col cols="12" md="2"><v-text-field v-model="videoCropWidth" label="裁剪宽" variant="outlined" /></v-col>
          <v-col cols="12" md="2"><v-text-field v-model="videoCropHeight" label="裁剪高" variant="outlined" /></v-col>
          <v-col cols="12" md="1"><v-text-field v-model="videoCropX" label="X" variant="outlined" /></v-col>
          <v-col cols="12" md="1"><v-text-field v-model="videoCropY" label="Y" variant="outlined" /></v-col>
        </v-row>
        <div class="d-flex ga-2">
          <v-btn variant="tonal" prepend-icon="mdi-play" @click="play">播放</v-btn>
          <v-btn variant="tonal" prepend-icon="mdi-pause" @click="pause">暂停</v-btn>
          <v-btn variant="tonal" prepend-icon="mdi-refresh" @click="seekStart">跳到起点</v-btn>
        </div>
      </template>
    </v-card>
  </v-container>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const videoRef = ref<HTMLVideoElement | null>(null);
const file = computed(() => (typeof route.query.file === 'string' ? decodeURIComponent(route.query.file) : ''));

const startTime = ref('');
const duration = ref('');
const videoCropWidth = ref('');
const videoCropHeight = ref('');
const videoCropX = ref('0');
const videoCropY = ref('0');

const toFileUrl = (path: string): string => `file://${path}`;

const saveEdits = (): void => {
  if (!file.value) return;
  localStorage.setItem(
    `aff-preview-${file.value}`,
    JSON.stringify({
      startTime: startTime.value,
      duration: duration.value,
      videoCropWidth: videoCropWidth.value,
      videoCropHeight: videoCropHeight.value,
      videoCropX: videoCropX.value,
      videoCropY: videoCropY.value
    })
  );
};

const play = (): void => {
  void videoRef.value?.play();
};
const pause = (): void => {
  videoRef.value?.pause();
};
const seekStart = (): void => {
  const sec = Number(startTime.value);
  if (Number.isFinite(sec) && sec >= 0 && videoRef.value) videoRef.value.currentTime = sec;
  else if (videoRef.value) videoRef.value.currentTime = 0;
};
</script>
