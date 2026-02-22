<template>
  <v-app>
    <v-layout class="fill-height">
      <v-navigation-drawer rail permanent>
        <v-list density="comfortable" nav>
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
      </v-navigation-drawer>

      <v-main>
        <router-view />
      </v-main>
    </v-layout>
  </v-app>
</template>

<script setup lang="ts">
const navItems = [
  { to: '/video', icon: 'mdi-filmstrip', title: '视频转换' },
  { to: '/audio', icon: 'mdi-music-note', title: '音频转换' },
  { to: '/media-edit', icon: 'mdi-movie-edit', title: '媒体编辑' },
  { to: '/tasks', icon: 'mdi-format-list-bulleted-square', title: '任务队列' },
  { to: '/logs', icon: 'mdi-text-box-search-outline', title: '应用日志' }
];
</script>
