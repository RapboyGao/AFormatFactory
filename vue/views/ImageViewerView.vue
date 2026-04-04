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
          @click="openFullscreen"
        >
          全屏预览
        </v-btn>
        <v-btn
          variant="tonal"
          prepend-icon="mdi-file-jpg-box"
          class="ml-2"
          :disabled="!images.length || exportInProgress"
          @click="exportJpeg"
        >
          批量导出 JPEG
        </v-btn>
        <v-btn variant="tonal" class="ml-2" :disabled="!images.length" @click="selectAllImages">全选</v-btn>
        <v-btn variant="tonal" class="ml-2" :disabled="!selectedImages.length" @click="deleteSelectedImages">删除选中</v-btn>
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
                  <v-btn
                    size="x-small"
                    variant="text"
                    :icon="selectedImages.includes(image) ? 'mdi-checkbox-marked-circle' : 'mdi-checkbox-blank-circle-outline'"
                    @click.stop="toggleImageSelection(image)"
                  />
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
                @dblclick="openFullscreen"
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

    <v-card v-if="exportInProgress || exportCompletedCount > 0" rounded="xl" class="pa-4 mt-4">
      <div class="d-flex align-center mb-2">
        <div class="text-subtitle-1">JPEG 导出进度</div>
        <v-spacer />
        <div class="text-caption text-medium-emphasis">{{ exportCompletedCount }}/{{ Math.max(1, exportTotalCount) }}</div>
      </div>
      <v-progress-linear :model-value="(exportCompletedCount / Math.max(1, exportTotalCount)) * 100" height="10" rounded />
      <div v-if="exportDirectory" class="text-caption text-medium-emphasis mt-2">{{ exportDirectory }}</div>
    </v-card>

    <Teleport to="body">
      <div v-if="isFullscreen" class="image-fullscreen-root">
        <div class="image-fullscreen-toolbar" @click.stop>
          <div>
            <div class="text-subtitle-1">{{ fileName(activeImage) }}</div>
            <div class="text-caption text-medium-emphasis">滚轮缩放 | 左键下一张 | 右键上一张</div>
          </div>
          <v-spacer />
          <v-switch v-model="slideshowEnabled" hide-details inset label="自动播放" class="mr-3" />
          <v-select
            v-model="slideshowInterval"
            :items="[1, 2, 3, 5, 10]"
            density="compact"
            hide-details
            variant="outlined"
            class="mr-3 fullscreen-interval"
          />
          <div class="text-caption text-medium-emphasis mr-4">{{ Math.round(fullscreenZoom * 100) }}%</div>
          <v-btn variant="tonal" prepend-icon="mdi-close" @click="closeFullscreen">退出全屏</v-btn>
        </div>

        <div
          class="image-fullscreen-stage"
          @wheel.prevent="onFullscreenWheel"
          @click="handleStageClick"
          @contextmenu.prevent="showPreviousImage"
          @mousemove="onDragMove"
          @mouseup="stopDrag"
          @mouseleave="stopDrag"
        >
          <img
            v-if="previewSrc"
            :src="previewSrc"
            :style="fullscreenImageStyle"
            class="image-fullscreen-image"
            draggable="false"
            @mousedown.left.prevent="startDrag"
          />
        </div>
      </div>
    </Teleport>
  </v-container>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { api } from '@/types/api';
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
const images = ref<string[]>([]);
const selectedImages = ref<string[]>([]);
const activeImage = ref<string>('');
const previewSrc = ref('');
const zoom = ref(1);
const pixelWidth = ref(0);
const pixelHeight = ref(0);
const fileSizeBytes = ref(0);
const isFullscreen = ref(false);
const fullscreenZoom = ref(1);
const fullscreenPanX = ref(0);
const fullscreenPanY = ref(0);
const exportInProgress = ref(false);
const exportCompletedCount = ref(0);
const exportTotalCount = ref(0);
const exportDirectory = ref('');
const slideshowEnabled = ref(false);
const slideshowInterval = ref(3);
const isDragging = ref(false);
const suppressNextClick = ref(false);
const dragStartX = ref(0);
const dragStartY = ref(0);
const panStartX = ref(0);
const panStartY = ref(0);
let slideshowTimer: ReturnType<typeof setInterval> | undefined;

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

const fullscreenImageStyle = computed(() => ({
  maxWidth: '84vw',
  maxHeight: '84vh',
  transform: `translate(${fullscreenPanX.value}px, ${fullscreenPanY.value}px) scale(${fullscreenZoom.value})`,
  transformOrigin: 'center center'
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
  selectedImages.value = [];
  await setActiveImage(selected[0] ?? '');
  void api.precacheImagePreviews(selected).catch((error) => {
    queue.pushLog(`图片预缓存失败: ${String(error)}`);
  });
};

const removeImage = (path: string): void => {
  images.value = images.value.filter((item) => item !== path);
  selectedImages.value = selectedImages.value.filter((item) => item !== path);
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

const selectAllImages = (): void => {
  selectedImages.value = [...images.value];
};

const toggleImageSelection = (path: string): void => {
  if (selectedImages.value.includes(path)) {
    selectedImages.value = selectedImages.value.filter((item) => item !== path);
  } else {
    selectedImages.value = [...selectedImages.value, path];
  }
};

const deleteSelectedImages = (): void => {
  if (!selectedImages.value.length) return;
  const removing = new Set(selectedImages.value);
  images.value = images.value.filter((item) => !removing.has(item));
  selectedImages.value = [];
  if (removing.has(activeImage.value)) {
    previewSrc.value = '';
    isFullscreen.value = false;
    const next = images.value[0] ?? '';
    if (next) {
      void setActiveImage(next);
    } else {
      activeImage.value = '';
      pixelWidth.value = 0;
      pixelHeight.value = 0;
      fileSizeBytes.value = 0;
      zoom.value = 1;
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
  const outputDirectory = await api.pickOutputDirectory();
  if (!outputDirectory) return;

  exportInProgress.value = true;
  exportCompletedCount.value = 0;
  exportTotalCount.value = images.value.length;
  exportDirectory.value = outputDirectory;

  try {
    const outputs: string[] = [];
    for (const inputPath of images.value) {
      const output = await api.exportImageAsJpegToDirectory(inputPath, outputDirectory);
      outputs.push(output);
      exportCompletedCount.value += 1;
    }
    queue.pushLog(`图片批量导出完成: ${outputs.length} 张`);
  } catch (error) {
    queue.pushLog(`图片导出失败: ${String(error)}`);
  } finally {
    exportInProgress.value = false;
  }
};

const openFullscreen = (): void => {
  if (!activeImage.value || !previewSrc.value) return;
  fullscreenZoom.value = 1;
  fullscreenPanX.value = 0;
  fullscreenPanY.value = 0;
  isFullscreen.value = true;
};

const closeFullscreen = (): void => {
  isFullscreen.value = false;
  slideshowEnabled.value = false;
};

const showNextImage = (): void => {
  if (!images.value.length) return;
  const currentIndex = images.value.indexOf(activeImage.value);
  const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % images.value.length : 0;
  fullscreenPanX.value = 0;
  fullscreenPanY.value = 0;
  void setActiveImage(images.value[nextIndex] ?? '');
};

const showPreviousImage = (): void => {
  if (!images.value.length) return;
  const currentIndex = images.value.indexOf(activeImage.value);
  const previousIndex = currentIndex > 0 ? currentIndex - 1 : images.value.length - 1;
  fullscreenPanX.value = 0;
  fullscreenPanY.value = 0;
  void setActiveImage(images.value[previousIndex] ?? '');
};

const onFullscreenWheel = (event: WheelEvent): void => {
  const delta = Math.max(-0.6, Math.min(0.6, event.deltaY / 600));
  fullscreenZoom.value = Math.max(0.2, Math.min(8, fullscreenZoom.value - delta));
};

const startDrag = (event: MouseEvent): void => {
  if (!isFullscreen.value) return;
  isDragging.value = true;
  suppressNextClick.value = false;
  dragStartX.value = event.clientX;
  dragStartY.value = event.clientY;
  panStartX.value = fullscreenPanX.value;
  panStartY.value = fullscreenPanY.value;
};

const onDragMove = (event: MouseEvent): void => {
  if (!isDragging.value) return;
  const dx = event.clientX - dragStartX.value;
  const dy = event.clientY - dragStartY.value;
  if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
    suppressNextClick.value = true;
  }
  fullscreenPanX.value = panStartX.value + dx;
  fullscreenPanY.value = panStartY.value + dy;
};

const stopDrag = (): void => {
  isDragging.value = false;
};

const handleStageClick = (): void => {
  if (suppressNextClick.value) {
    suppressNextClick.value = false;
    return;
  }
  showNextImage();
};

const handleKeydown = (event: KeyboardEvent): void => {
  if (!isFullscreen.value) return;
  if (event.key === 'ArrowLeft') {
    event.preventDefault();
    showPreviousImage();
  } else if (event.key === 'ArrowRight') {
    event.preventDefault();
    showNextImage();
  } else if (event.key === 'Escape') {
    event.preventDefault();
    closeFullscreen();
  }
};

const refreshSlideshow = (): void => {
  if (slideshowTimer) {
    clearInterval(slideshowTimer);
    slideshowTimer = undefined;
  }
  if (isFullscreen.value && slideshowEnabled.value) {
    slideshowTimer = setInterval(() => {
      showNextImage();
    }, slideshowInterval.value * 1000);
  }
};

watch([isFullscreen, slideshowEnabled, slideshowInterval], refreshSlideshow);

onMounted(() => {
  window.addEventListener('keydown', handleKeydown);
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown);
  if (slideshowTimer) clearInterval(slideshowTimer);
});
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

.image-fullscreen-root {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background:
    radial-gradient(circle at top, rgba(255, 255, 255, 0.05), transparent 28%),
    linear-gradient(180deg, rgba(5, 8, 14, 0.985), rgba(10, 12, 18, 0.995));
}

.image-fullscreen-toolbar {
  position: absolute;
  inset: 0 0 auto 0;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 18px 22px;
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.42), rgba(0, 0, 0, 0));
}

.image-fullscreen-stage {
  position: absolute;
  inset: 0;
  overflow: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 32px;
}

.image-fullscreen-image {
  display: block;
  height: auto;
  border-radius: 20px;
  box-shadow: 0 28px 80px rgba(0, 0, 0, 0.55);
  user-select: none;
  -webkit-user-drag: none;
  cursor: grab;
}

.fullscreen-interval {
  width: 88px;
}

</style>
