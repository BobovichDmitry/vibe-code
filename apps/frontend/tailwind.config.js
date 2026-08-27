/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    './app.vue',
    './error.vue',
    './pages/**/*.{vue,js,ts}',
    './layouts/**/*.{vue,js,ts}',
    './components/**/*.{vue,js,ts}',
    './composables/**/*.{js,ts}',
    './plugins/**/*.{js,ts}',
    './nuxt.config.{js,ts}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#eef2ff',
          100: '#e0e7ff',
          500: '#6366f1',
          600: '#4f46e5',
          700: '#4338ca',
        },
      },
      boxShadow: {
        soft: '0 10px 30px -12px rgba(15, 23, 42, 0.18)',
      },
    },
  },
  plugins: [],
};