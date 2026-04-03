<template>
  <v-app>
    <v-layout class="fill-height">
      <v-navigation-drawer v-if="!isPreviewRoute" width="260" permanent>
        <v-sheet class="pa-4">
          <div class="text-h6">AFormatFactory</div>
          <div class="text-caption text-medium-emphasis">Tauri + Vue + FFmpeg C API</div>
        </v-sheet>
        <v-divider />
        <v-list density="comfortable" nav class="pt-2">
          <v-list-item
            v-for="item in navItems"
            :key="item.to"
            :to="item.to"
            router
            rounded="lg"
            :prepend-icon="item.icon"
            :title="item.title"
          />
        </v-list>
        <template #append>
          <v-sheet class="pa-4">
            <v-row dense>
              <v-col cols="6"><v-chip size="small" block>总 {{ queue.stats.total }}</v-chip></v-col>
              <v-col cols="6"><v-chip size="small" color="primary" block>运行 {{ queue.stats.running }}</v-chip></v-col>
              <v-col cols="6"><v-chip size="small" color="success" block>成功 {{ queue.stats.success }}</v-chip></v-col>
              <v-col cols="6"><v-chip size="small" color="error" block>失败 {{ queue.stats.failed }}</v-chip></v-col>
            </v-row>
          </v-sheet>
        </template>
      </v-navigation-drawer>

      <v-main>
        <v-app-bar v-if="!isPreviewRoute" flat border>
          <v-app-bar-title>{{ currentTitle }}</v-app-bar-title>
        </v-app-bar>
        <router-view />
      </v-main>
    </v-layout>
  </v-app>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const route = useRoute();

const navItems = [
  { to: '/video', icon: 'mdi-filmstrip', title: '视频转换' },
  { to: '/audio', icon: 'mdi-music-note', title: '音频转换' },
  { to: '/media-edit', icon: 'mdi-movie-edit', title: '媒体编辑' },
  { to: '/images', icon: 'mdi-image-multiple-outline', title: '图片查看器' },
  { to: '/tasks', icon: 'mdi-format-list-bulleted-square', title: '任务队列' },
  { to: '/logs', icon: 'mdi-text-box-search-outline', title: '应用日志' }
];

const currentTitle = computed(() => navItems.find((x) => x.to === route.path)?.title ?? 'AFormatFactory');
const isPreviewRoute = computed(() => route.path === '/preview');

onMounted(() => void queue.bootstrap());
</script>
