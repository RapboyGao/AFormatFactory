<template>
  <v-container fluid class="pa-6">
    <v-card rounded="xl" class="pa-4">
      <v-card-title class="text-h6">应用日志</v-card-title>
      <v-divider class="my-3" />
      <v-list density="compact" lines="one">
        <v-list-item v-for="(line, index) in queue.appLogs" :key="index" :title="line" />
      </v-list>
    </v-card>
  </v-container>
</template>

<script setup lang="ts">
import { useQueueStore } from '@/stores/queue';

const queue = useQueueStore();
</script>
