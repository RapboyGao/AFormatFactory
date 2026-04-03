<template>
  <v-container fluid class="pa-6">
    <v-card rounded="xl" class="pa-5">
      <div class="d-flex align-center mb-4">
        <div class="text-h6">HEIC / HIF / HEIF 图片查看器</div>
        <v-spacer />
        <v-btn variant="tonal" prepend-icon="mdi-image-search-outline" @click="selectImages">选择图片</v-btn>
        <v-btn
          variant="tonal"
          prepend-icon="mdi-fullscreen"
          class="ml-2"
          :disabled="!activeImage || !previewSrc"
          @click="isFullscreen = true"
        >
          全屏预览
        </v-btn>
        <v-btn
          variant="tonal"
          prepend-icon="mdi-file-jpg-box"
          class="ml-2"
          :disabled="!images.length"
          @click="exportJpeg"
        >
          批量导出 JPEG
        </v-btn>
      </div>

      <v-row>
        <v-col cols="12" lg="4">
          <v-card rounded="xl" variant="outlined" class="pa-3 panel-shell">
            <div class="text-subtitle-1 mb-3">已选图片 ({{ images.length }})</div>
            <div v-if="!images.length" class="text-medium-emphasis">尚未选择图片</div>
            <v-list v-else density="compact" class="bg-transparent">
              <v-list-item
                v-for="(image, index) in images"
                :key="image"
                rounded="lg"
                :active="image === activeImage"
                @click="setActiveImage(image)"
              >
                <template #prepend>
                  <div class="text-caption text-medium-emphasis mr-3" style="width: 22px">{{ index + 1 }}</div>
                </template>
                <v-list-item-title class="text-body-2">{{ fileName(image) }}</v-list-item-title>
                <v-list-item-subtitle>{{ image }}</v-list-item-subtitle>
                <template #append>
                  <v-btn size="small" icon="mdi-close" variant="text" @click.stop="removeImage(image)" />
                </template>
              </v-list-item>
            </v-list>
          </v-card>
        </v-col>

        <v-col cols="12" lg="8">
          <v-card rounded="xl" variant="outlined" class="pa-3 panel-shell">
            <div class="d-flex align-center mb-3">
              <div class="text-subtitle-1">图片预览</div>
              <v-spacer />
              <div class="text-caption text-medium-emphasis">{{ imageInfo }}</div>
            </div>

            <div v-if="!activeImage" class="viewer-empty">
              <v-icon icon="mdi-image-off-outline" size="52" />
              <div>选择一张 HEIC/HIF/HEIF 图片后开始查看</div>
            </div>
            <div v-else class="viewer-frame">
              <img
                v-if="previewSrc"
                :src="previewSrc"
                :style="imageStyle"
                class="viewer-image"
                @load="onImageLoad"
                @dblclick="isFullscreen = true"
              />
              <div v-else class="viewer-loading">正在生成预览...</div>
            </div>

            <div class="d-flex align-center mt-4 ga-3">
              <div class="text-caption text-medium-emphasis">缩放</div>
              <v-slider v-model="zoom" :min="0.1" :max="4" :step="0.05" hide-details />
              <div class="text-caption text-medium-emphasis" style="width: 56px; text-align: right">
                {{ Math.round(zoom * 100) }}%
              </div>
            </div>
          </v-card>
        </v-col>
      </v-row>
    </v-card>

    <v-dialog v-model="isFullscreen" fullscreen scrim="black">
      <v-card class="fullscreen-shell">
        <div class="fullscreen-toolbar">
          <div class="text-subtitle-1">{{ fileName(activeImage) }}</div>
          <v-spacer />
          <v-btn variant="tonal" prepend-icon="mdi-close" @click="isFullscreen = false">退出全屏</v-btn>
        </div>
        <div class="fullscreen-frame" @click.self="isFullscreen = false">
          <img v-if="previewSrc" :src="previewSrc" class="fullscreen-image" />
        </div>
      </v-card>
    </v-dialog>
  </v-container>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { api } from '@/types/api';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const images = ref<string[]>([]);
const activeImage = ref<string>('');
const previewSrc = ref('');
const zoom = ref(1);
const pixelWidth = ref(0);
const pixelHeight = ref(0);
const fileSizeBytes = ref(0);
const isFullscreen = ref(false);

const imageInfo = computed(() => {
  if (!activeImage.value || pixelWidth.value <= 0 || pixelHeight.value <= 0) {
    return activeImage.value ? fileName(activeImage.value) : '无选中图片';
  }
  const mb = fileSizeBytes.value > 0 ? ` | ${(fileSizeBytes.value / 1_048_576).toFixed(2)} MB` : '';
  return `${pixelWidth.value} x ${pixelHeight.value}${mb}`;
});

const imageStyle = computed(() => ({
  width: `${Math.max(120, pixelWidth.value * zoom.value)}px`,
  maxWidth: 'none'
}));

const fileName = (path: string): string => path.split('/').pop() || path;

const setActiveImage = async (path: string): Promise<void> => {
  activeImage.value = path;
  zoom.value = 1;
  pixelWidth.value = 0;
  pixelHeight.value = 0;
  previewSrc.value = '';
  fileSizeBytes.value = 0;

  try {
    const result = await api.renderImagePreview(path);
    previewSrc.value = result.preview_data_url;
    fileSizeBytes.value = result.file_size_bytes;
  } catch (error) {
    queue.pushLog(`图片预览失败: ${String(error)}`);
  }
};

const selectImages = async (): Promise<void> => {
  const selected = await api.pickImageFiles();
  if (!selected.length) return;
  images.value = selected;
  await setActiveImage(selected[0] ?? '');
};

const removeImage = (path: string): void => {
  images.value = images.value.filter((item) => item !== path);
  if (activeImage.value === path) {
    previewSrc.value = '';
    isFullscreen.value = false;
    if (images.value[0]) {
      void setActiveImage(images.value[0]);
    } else {
      activeImage.value = '';
      pixelWidth.value = 0;
      pixelHeight.value = 0;
      zoom.value = 1;
      fileSizeBytes.value = 0;
    }
  }
};

const onImageLoad = (event: Event): void => {
  const target = event.target as HTMLImageElement;
  pixelWidth.value = target.naturalWidth;
  pixelHeight.value = target.naturalHeight;
};

const exportJpeg = async (): Promise<void> => {
  if (!images.value.length) return;
  try {
    const outputs = await api.exportImagesAsJpeg(images.value);
    queue.pushLog(`图片批量导出完成: ${outputs.length} 张`);
  } catch (error) {
    queue.pushLog(`图片导出失败: ${String(error)}`);
  }
};
</script>

<style scoped>
.panel-shell {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.08) !important;
}

.viewer-frame {
  display: flex;
  justify-content: center;
  align-items: flex-start;
  overflow: auto;
  min-height: 560px;
  max-height: 72vh;
  padding: 20px;
  border-radius: 20px;
  background:
    radial-gradient(circle at top, rgba(255, 255, 255, 0.08), transparent 35%),
    linear-gradient(180deg, rgba(10, 14, 22, 0.96), rgba(18, 24, 34, 0.92));
}

.viewer-image {
  display: block;
  height: auto;
  border-radius: 16px;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
}

.viewer-empty {
  min-height: 560px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  align-items: center;
  justify-content: center;
  color: rgba(255, 255, 255, 0.55);
  border-radius: 20px;
  background:
    radial-gradient(circle at center, rgba(255, 255, 255, 0.05), transparent 40%),
    linear-gradient(180deg, rgba(10, 14, 22, 0.96), rgba(18, 24, 34, 0.92));
}

.viewer-loading {
  min-height: 560px;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(255, 255, 255, 0.65);
}

.fullscreen-shell {
  background:
    radial-gradient(circle at top, rgba(255, 255, 255, 0.06), transparent 30%),
    linear-gradient(180deg, rgba(8, 10, 16, 0.98), rgba(12, 14, 20, 1));
}

.fullscreen-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 20px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.fullscreen-frame {
  height: calc(100vh - 72px);
  overflow: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.fullscreen-image {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  border-radius: 18px;
  box-shadow: 0 24px 70px rgba(0, 0, 0, 0.55);
}
</style>
