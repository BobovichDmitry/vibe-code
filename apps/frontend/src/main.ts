import { createApp } from 'vue';
import App from './App.vue';
import router from './router';
import { useTheme } from './composables/useTheme';
import { loadBranding } from './composables/useBranding';
import './style.css';

const app = createApp(App);
const theme = useTheme();

app.provide('theme', theme);
app.config.globalProperties.$theme = theme;
app.use(router);
app.mount('#app');

// Загрузить брендинг с бэкенда (публичный эндпоинт, без JWT)
loadBranding();
