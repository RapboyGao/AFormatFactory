import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { createVuetify } from 'vuetify';
import 'vuetify/styles';
import { aliases, mdi } from 'vuetify/iconsets/mdi';
import '@mdi/font/css/materialdesignicons.css';
import App from './App.vue';
import { router } from './router';

const vuetify = createVuetify({
  theme: {
    defaultTheme: 'darkAFactory',
    themes: {
      darkAFactory: {
        dark: true,
        colors: {
          background: '#0f141d',
          surface: '#141b26',
          'surface-bright': '#1a2331',
          primary: '#4fc3f7',
          secondary: '#8aa2c7',
          success: '#7bc99a',
          warning: '#ffca6b',
          error: '#ff6b81'
        }
      }
    }
  },
  icons: {
    defaultSet: 'mdi',
    aliases,
    sets: { mdi }
  }
});

createApp(App).use(createPinia()).use(router).use(vuetify).mount('#app');
