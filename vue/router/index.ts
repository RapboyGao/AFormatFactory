import { createRouter, createWebHashHistory } from 'vue-router';
import VideoConvertView from '@/views/VideoConvertView.vue';
import AudioConvertView from '@/views/AudioConvertView.vue';
import MediaEditView from '@/views/MediaEditView.vue';
import TasksView from '@/views/TasksView.vue';
import LogsView from '@/views/LogsView.vue';
import PreviewEditorView from '@/views/PreviewEditorView.vue';
import ImageViewerView from '@/views/ImageViewerView.vue';

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', redirect: '/video' },
    { path: '/video', component: VideoConvertView },
    { path: '/audio', component: AudioConvertView },
    { path: '/media-edit', component: MediaEditView },
    { path: '/images', component: ImageViewerView },
    { path: '/tasks', component: TasksView },
    { path: '/logs', component: LogsView },
    { path: '/preview', component: PreviewEditorView }
  ]
});
