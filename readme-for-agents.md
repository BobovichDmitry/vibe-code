# Setup Guide for AI Agents

This document contains step-by-step instructions for AI agents to clone, install, configure, and run this project on a server using plain Node.js (no Docker, no domains).

**Repository URL**: `git@git.obvu.ru:amorev/vibecode-setup.git`

---

## Prerequisites

The server must have:
- **Node.js 20+** (v24.x tested). Install via `nvm` or package manager.
- **npm 10+** (shipped with Node.js 20+).
- **git** (for cloning and future updates).
- **SQLite** is bundled via `sqlite3` npm package — no separate installation needed.

Check with:
```bash
node --version    # must be >= 20
npm --version     # must be >= 10
git --version
```

---

## Step 1: Clone the Repository

Clone the repo into a directory on the server. **Preserve the `origin` remote** so updates can be pulled later:

```bash
cd /opt
git clone git@git.obvu.ru:amorev/vibecode-setup.git vibe-setup-ui
cd vibe-setup-ui
```

Verify the remote is set correctly:
```bash
git remote -v
# Expected output:
# origin  git@git.obvu.ru:amorev/vibecode-setup.git (fetch)
# origin  git@git.obvu.ru:amorev/vibecode-setup.git (push)
```

> **Important**: Do NOT delete or replace the `origin` remote. Future updates from the original repository will be pulled via `git pull origin master`.

---

## Step 2: Install Dependencies

```bash
npm install
```

This installs all workspace dependencies (`apps/backend`, `apps/frontend`, `e2e`) and root dependencies.

---

## Step 3: Configure Environment Variables

### Backend (required)

Copy the template and edit:

```bash
cp apps/backend/.env.example apps/backend/.env
```

Edit `apps/backend/.env` — **at minimum change these values**:

| Variable | Default | Action |
|----------|---------|--------|
| `JWT_SECRET` | `dev-secret-change-me` | **CHANGE**: set a random strong string |
| `ADMIN_LOGIN` | `admin` | Change to desired admin username |
| `ADMIN_PASSWORD` | `admin` | Change to desired admin password |
| `PORT` | `3000` | Change if port 3000 is occupied |
| `CORS_ORIGIN` | `http://localhost:5173,http://localhost:3000` | Set to the actual host where the app will be accessed (e.g., `http://server-ip:3000`) |

Example production `.env`:
```
DB_TYPE=sqlite
DB_SQLITE_PATH=./data/database.sqlite
PORT=3000
JWT_SECRET=your-random-secret-here-change-this
ADMIN_LOGIN=admin
ADMIN_PASSWORD=strong-password-here
CORS_ORIGIN=http://localhost:3000
```

### Frontend (optional)

The frontend `.env` uses sensible defaults. Only change if the API is on a different host:

```bash
# apps/frontend/.env
VITE_API_BASE_URL=/
```

Leave as `/` — in production the frontend is served by the backend on the same origin.

---

## Step 4: Build the Application

Build both frontend and backend:

```bash
npm run build
```

This runs:
1. `npm run build:frontend` — compiles Vue 3 SPA into `apps/frontend/dist/`
2. `npm run build:backend` — compiles Nest.js into `apps/backend/dist/`

---

## Step 5: Start the Production Server

```bash
npm run start:prod
```

This starts a single Node.js process that:
- Serves the backend API at `/api/*`
- Serves the frontend static files at `/`
- Handles SPA fallback (routes without `/api` go to `index.html`)

The server listens on the port from `PORT` env variable (default `3000`).

### Running as a background process

Use `pm2` (recommended for production) or `nohup`:

**With pm2:**
```bash
npm install -g pm2
pm2 start npm --name "vibe-setup-ui" -- start:prod
pm2 save
pm2 startup   # auto-start on boot
```

**With nohup:**
```bash
nohup npm run start:prod > /var/log/vibe-setup-ui.log 2>&1 &
```

---

## Step 6: Verify the Application

Open a browser or use curl:

```bash
# Check API health
curl http://localhost:3000/api/users/count

# Login with admin credentials
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"login":"admin","password":"your-password"}'
```

The response from `/api/auth/login` should return `{ "access_token": "..." }`.

---

## Updating the Application

When new versions are pushed to the repository:

```bash
cd /opt/vibe-setup-ui

# 1. Save current local changes (if any)
git stash

# 2. Pull updates from origin
git pull origin master

# 3. If there are merge conflicts, resolve them:
#    - Review the conflicted files
#    - Fix conflicts (preserve your local customizations)
#    - git add <resolved-files>
#    - git commit

# 4. Reinstall dependencies (package.json may have changed)
npm install

# 5. Rebuild
npm run build

# 6. Restart the server
# With pm2:
pm2 restart vibe-setup-ui

# With nohup: find the PID and kill, then restart
```

### Applying environment variable changes

After pulling, check if new env variables were added:

```bash
# Compare .env.example with current .env
diff apps/backend/.env.example apps/backend/.env
```

Add any new variables to your `.env` file.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `EADDRINUSE` on port 3000 | `lsof -i :3000` to find the PID, then `kill <PID>` or change `PORT` in `.env` |
| `sqlite3` build fails | Ensure `python3` and `make` are installed: `apt install python3 make gcc g++` |
| Frontend not served | Run `npm run build:frontend` first; verify `apps/frontend/dist/index.html` exists |
| 401 Unauthorized | Check `JWT_SECRET` is set; ensure the token is passed as `Authorization: Bearer <token>` |
| CORS errors | Add the frontend's URL to `CORS_ORIGIN` in `apps/backend/.env` |
| First admin not created | Delete `apps/backend/data/database.sqlite` and restart — admin is auto-created on empty DB |

---

## Architecture Summary

```
vibe-setup-ui/
├── apps/
│   ├── backend/              # Nest.js API
│   │   ├── src/
│   │   │   ├── auth/         # JWT auth (login, me, password)
│   │   │   ├── users/        # User CRUD (admin only)
│   │   │   ├── database/     # SQLite/PostgreSQL TypeORM
│   │   │   ├── main.ts       # Entry point
│   │   │   └── app.module.ts # Root module
│   │   ├── .env              # Environment config
│   │   └── .env.example      # Template
│   └── frontend/             # Vue 3 + Tailwind SPA
│       ├── src/
│       │   ├── api/          # Axios clients
│       │   ├── views/        # Page components
│       │   ├── router/       # Hash router
│       │   └── composables/  # useAuth
│       └── vite.config.ts
├── e2e/                      # Playwright tests
├── scripts/                  # log-runner, kill-service
├── package.json              # Root workspace
└── readme-for-agents.md      # ← This file
```

### API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/login` | No | Login → `{ access_token }` |
| GET | `/api/auth/me` | JWT | Current user info |
| PATCH | `/api/auth/password` | JWT | Change password |
| GET | `/api/users` | Admin | List all users |
| GET | `/api/users/:id` | Admin | Get single user |
| POST | `/api/users` | Admin | Create user |
| PATCH | `/api/users/:id` | Admin | Update user |
| DELETE | `/api/users/:id` | Admin | Delete user |
| GET | `/api/users/count` | No | Public user count |
