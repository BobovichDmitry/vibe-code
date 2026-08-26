import { createRouter, createWebHashHistory } from 'vue-router';

const requireAuth = (to: any, from: any, next: any) => {
  const token = localStorage.getItem('auth_token');
  if (!token) {
    next({ name: 'login' });
  } else {
    next();
  }
};

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/',
      name: 'home',
      component: () => import('@/views/PublicView.vue'),
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { guest: true },
    },
    {
      path: '/admin',
      component: () => import('@/layouts/AdminLayout.vue'),
      beforeEnter: requireAuth,
      redirect: { name: 'admin-users' },
      children: [
        {
          path: '',
          name: 'admin-users',
          component: () => import('@/views/admin/ManageUsersView.vue'),
        },
        {
          path: 'files',
          name: 'admin-files',
          component: () => import('@/views/admin/ManageFilesView.vue'),
        },
      ],
    },
  ],
});

export default router;
