# The 24-Hour Task App — Product & Technical Spec

**Name:** 24 (repo: `twentyfour`)
**Domain:** `24.namastevis.in`
**Host:** Hostinger VPS · source public on GitHub · deploy via GitHub Actions over SSH
**Author:** spec v2, Aug 2026

### Decisions locked

| Question | Answer |
|---|---|
| DECIDED exit | **Requires a real date.** Free text is not accepted. |
| Clock start | **Strict wall-clock 24h from capture.** Not end-of-next-day. `captured_at` is immutable. |
| Hard block on capture while in debt | **No.** Too likely to make you stop capturing. |
| Users | **Single user, permanently.** Passphrase + bearer cookie, no account system. |
| Repo | **Public, but built for one person.** No self-host docs, nothing personal committed. |

---

## 1. Why existing todo apps fail you

This is worth naming precisely, because it determines every design decision below.

| What todo apps do | Why it breaks the habit you want |
|---|---|
| Due dates are optional and user-set | You set them, then move them. The app never objects. |
| Priority flags (P1/P2/P3) | Priority is a *feeling*, and it's re-negotiable. Age is a *fact*. |
| Snooze / "Someday" / "Later" lists | An infinite escape hatch. Tasks go there to die quietly. |
| Completion count as the metric | Rewards doing 20 easy things while one hard thing rots for 6 weeks. |
| Overdue items look identical to fresh ones | No cost to delay, so delay is free. |
| Capture is 4 taps deep | The clock starts late, or the task never gets captured at all. |

**The single change this app makes:** *time since capture* is the only ranking signal, and it is impossible to hide from.

---

## 2. The core contract

> Every task you write down gets **resolved within 24 hours of capture**.
> "Resolved" does not mean "done."

### The four exits

A task leaves the active list exactly one way — you pick one of four:

| Exit | Meaning | Keyboard |
|---|---|---|
| **DONE** | You did it. | `D` |
| **DELEGATED** | Someone else owns it now. You record who. | `G` |
| **DROPPED** | You've decided it doesn't matter. No guilt, no archive shame. | `X` |
| **DECIDED** | You now *know* what this is and when it happens. **A date is mandatory.** It leaves the list and returns as a fresh task with a new 24h clock. | `S` |

**Design note:** DROPPED must be one keystroke and produce zero friction or negative feedback. If dropping feels bad, you will avoid the app entirely rather than drop things. Dropping is a *success* — it's a decision made within 24h.

**Design note:** DECIDED is the escape valve for "this genuinely takes 3 weeks." The date field is required and validated — this is what stops it degenerating into a snooze button. DELEGATED likewise requires a name, because delegation without an owner is just delay.

### What is deliberately NOT in the app

- No snooze
- No "someday/maybe" list
- No sub-tasks or nested projects
- No user-editable due dates
- No priority field
- No tags at launch (maybe one "context" field in v2)

Every one of these is a way to avoid the 24h decision. Adding them kills the app.

---

## 3. The decay model

The clock starts at `captured_at`. Not at a due date. Not at a start date. **Capture time is immutable and cannot be edited** — this is the load-bearing constraint.

### Stages

| Stage | Age | Visual treatment | Behavior |
|---|---|---|---|
| **Fresh** | 0–24h | Full opacity, neutral ink, thin border. Shows countdown: `18h left` | Normal position in list |
| **Slipping** | 24–48h | Amber left-edge bar. Background warms slightly. Shows `+7h over` | Pinned above all Fresh tasks |
| **Rotting** | 48–96h | Red edge, text desaturates to ~70%, background gains a subtle noise/grain texture. `+2d over` | Pinned to top. Card gains a faint animated jitter on load. |
| **Fossil** | 96h+ | Heavy desaturation (grayscale ~80%), reduced opacity, cracked-border effect, age in days at large type | Moved into a **Fossil Bed** section at the very top with a single prompt: *"These are dead. Drop them?"* and a **Drop All** button. |

### Decay math (drives CSS variables)

```
age_h      = (now - captured_at) / 3600
overdue_h  = max(0, age_h - 24)
rot        = min(1, overdue_h / 72)      // 0 at 24h, 1.0 at 96h

--decay-saturate : 1 - (rot * 0.8)
--decay-opacity  : 1 - (rot * 0.35)
--decay-hue      : mix(neutral -> amber -> red, by rot)
--decay-grain    : rot * 0.4              // noise overlay alpha
```

Recompute on a 60s interval and on tab focus. Pure CSS custom properties per card so the DOM doesn't thrash.

### The counter that matters

Top of screen, always visible, two numbers:

- **DEBT** — count of open tasks past 24h. Target: `0`.
- **RATE** — % of tasks captured in the last 7 days that were resolved within 24h. Target: `>90%`.

RATE is the habit metric. It is the *only* stat on the home screen. A 7-day sparkline sits under it.

### Daily Reckoning

Once a day (default 9pm, configurable), the app enters a modal state showing every task that will cross 24h in the next 3 hours. You must pick an exit for each before dismissing. This is the forcing function that makes the habit stick — a todo app you don't open is a todo app that does nothing.

Delivered as: in-app modal + web push notification (PWA) + optional email fallback.

---

## 4. Data model

SQLite. One file. Trivial to back up.

```sql
CREATE TABLE tasks (
  id            TEXT PRIMARY KEY,          -- uuid v7 (time-sortable)
  body          TEXT NOT NULL,
  captured_at   INTEGER NOT NULL,          -- unix seconds, IMMUTABLE
  source        TEXT NOT NULL DEFAULT 'app', -- app | email | share | api
  resolved_at   INTEGER,                   -- null while open
  resolution    TEXT,                      -- done | delegated | dropped | decided
  delegated_to  TEXT,                      -- required when resolution='delegated'
  decided_for   TEXT,                      -- YYYY-MM-DD, required when resolution='decided'
  parent_id     TEXT REFERENCES tasks(id), -- DECIDED spawns a child with a fresh clock
  device_id     TEXT,
  updated_at    INTEGER NOT NULL
);

CREATE INDEX idx_open ON tasks(resolved_at, captured_at);

-- append-only audit trail; enables honest stats and undo
CREATE TABLE events (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id   TEXT NOT NULL,
  kind      TEXT NOT NULL,   -- captured | resolved | unresolved | edited
  payload   TEXT,            -- json
  at        INTEGER NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY, value TEXT
);
```

**Derived, never stored:** `age`, `stage`, `rot`, `debt`, `rate`. Computing these live means the clock can't be gamed by editing a field.

**Undo:** 10-second undo toast after any resolution, implemented by writing an `unresolved` event and nulling `resolved_at`. After 10s it's final — no un-archiving from a history screen. (Reopening old tasks is how backlogs are reborn.)

---

## 5. API

Single user. Small surface.

```
POST   /api/tasks              { body, source? }        -> task
GET    /api/tasks?open=1                                -> task[]
POST   /api/tasks/:id/resolve  { resolution, note? }    -> task
POST   /api/tasks/:id/unresolve                         -> task
PATCH  /api/tasks/:id          { body }                 -> task   (body only; never captured_at)
GET    /api/stats                                       -> { debt, rate7, spark[] }
POST   /api/sync               { since, mutations[] }   -> { tasks[], cursor }
```

**Auth:** single-user, so skip account systems. Use a long random bearer token stored in an httpOnly cookie, set once via a `/login` page with a passphrase from an env var. Rate-limit the login route. That's enough for a personal app on your own domain.

**Offline sync:** the client is local-first. Writes go to IndexedDB immediately and queue a mutation. A background loop POSTs `/api/sync` with the queue. Conflict rule: **last-write-wins on `updated_at`, except `captured_at` and the first `resolved_at`, which are immutable once set.** This is simple and correct for a single user on 2–3 devices.

---

## 6. Screens

### A. Capture (the most important screen)

- A permanently-focused input at the top on desktop. Type, hit Enter, it's captured, input clears. Zero modals.
- Global hotkey on desktop: `Ctrl/Cmd + Shift + K` opens the app to a focused input.
- On mobile: PWA installed to home screen; app opens directly to keyboard-up capture. Registered as a **Web Share Target** so you can share a link/text from any app straight into the list.
- Capture confirmation is a single line: `captured · 24h clock started`.

### B. The List (home)

```
┌────────────────────────────────────────────┐
│  DEBT 3          RATE 82%    ▁▃▅▂▆▇▅        │
├────────────────────────────────────────────┤
│  FOSSIL BED (2)              [ Drop all ]  │
│  ▓ call the accountant           6d        │
│  ▓ reply to Priya re: contract   4d        │
├────────────────────────────────────────────┤
│  ▐ book flights              +2d over      │
│  ▐ fix the invoice script    +9h over      │
├────────────────────────────────────────────┤
│  │ draft the Q3 note           18h left    │
│  │ email landlord               22h left   │
└────────────────────────────────────────────┘
```

- Strict sort: Fossil → Rotting → Slipping → Fresh, each by oldest first.
- Desktop: `j`/`k` to move, then `D`/`G`/`X`/`K` to resolve. Whole flow is keyboard-only.
- Mobile: swipe right = DONE, swipe left = reveals DROPPED / DELEGATED / DECIDED.

### C. Daily Reckoning

Full-screen, one task at a time, four big buttons. Cannot be dismissed until every at-risk task has an exit. Escapable only with an explicit "skip tonight" that is logged and shown in stats as a broken streak.

### D. Stats (secondary tab)

7/30/90-day RATE, distribution of exits (how much are you dropping vs doing — useful signal), median time-to-resolution, longest current streak of zero-debt days.

---

## 7. Stack

Given a VPS, keep it boring and self-contained.

| Layer | Choice | Why |
|---|---|---|
| Frontend | **Vite + React + TypeScript + Tailwind** | Fast build, PWA plugin is one line, you'll be able to iterate on the decay visuals quickly |
| Offline store | **Dexie (IndexedDB)** | Local-first, tiny |
| Backend | **Node 22 + Fastify** | One process, low memory — fits Hostinger's smallest VPS |
| DB | **SQLite via better-sqlite3** | Single file, synchronous, no separate service to run or secure |
| Reverse proxy / TLS | **Caddy** | Automatic Let's Encrypt certs, 5-line config. Simpler than nginx + certbot. |
| Process mgmt | **systemd** | Already there, no pm2 needed |
| Push | **Web Push (VAPID)** via `web-push` | Free, works on installed PWAs on Android + iOS 16.4+ |

Total server footprint: ~120MB RAM. Runs comfortably on a 1GB VPS.

**Repo layout**

```
halflife/
  client/           # vite react pwa
  server/           # fastify + sqlite
  server/data/      # halflife.db  (gitignored, backed up)
  Caddyfile
  deploy.sh
  halflife.service
```

---

## 8. Deploy plan (Hostinger VPS)

**Prereqs:** Ubuntu 22/24 VPS, root SSH, domain DNS managed where you bought it.

1. **DNS** — add an `A` record: `do.namastevis.xxx → <VPS IP>`. TTL 300. Wait for propagation (`dig do.namastevis.xxx`).

2. **Harden the box** — create a non-root user, add your SSH key, disable password auth and root login in `/etc/ssh/sshd_config`, enable `ufw` allowing only 22/80/443.

3. **Install runtime**
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs build-essential   # build-essential for better-sqlite3
   ```

4. **Install Caddy** (`apt` repo from caddyserver.com), then `/etc/caddy/Caddyfile`:
   ```
   do.namastevis.xxx {
     handle /api/* {
       reverse_proxy localhost:8080
     }
     handle {
       root * /srv/halflife/client
       try_files {path} /index.html
       file_server
     }
   }
   ```
   Caddy fetches the TLS cert automatically on first request.

5. **App user + directories**
   ```bash
   sudo useradd -r -s /usr/sbin/nologin halflife
   sudo mkdir -p /srv/halflife/{client,server,data}
   sudo chown -R halflife: /srv/halflife
   ```

6. **systemd unit** `/etc/systemd/system/halflife.service`
   ```ini
   [Unit]
   After=network.target
   [Service]
   User=halflife
   WorkingDirectory=/srv/halflife/server
   EnvironmentFile=/srv/halflife/server/.env
   ExecStart=/usr/bin/node dist/index.js
   Restart=always
   [Install]
   WantedBy=multi-user.target
   ```
   `.env` holds `PORT=8080`, `PASSPHRASE=…`, `VAPID_PUBLIC/PRIVATE=…`, `DB_PATH=/srv/halflife/data/halflife.db`. Mode `600`.

7. **Deploy script** — build locally, rsync artifacts up, restart service:
   ```bash
   npm --prefix client run build
   npm --prefix server run build
   rsync -az client/dist/  user@vps:/srv/halflife/client/
   rsync -az server/dist/ server/package*.json user@vps:/srv/halflife/server/
   ssh user@vps 'cd /srv/halflife/server && npm ci --omit=dev && sudo systemctl restart halflife'
   ```
   Upgrade to a GitHub Actions workflow doing the same over SSH once it's stable.

8. **Backups** — nightly cron, since SQLite backup is one command:
   ```
   0 3 * * * sqlite3 /srv/halflife/data/halflife.db ".backup '/srv/halflife/data/bk-$(date +\%F).db'" && find /srv/halflife/data -name 'bk-*.db' -mtime +14 -delete
   ```
   Then rclone/scp the backup dir offsite weekly. Also expose `GET /api/export` returning full JSON — your data should never be trapped.

9. **PWA install** — visit the domain on your phone, "Add to Home Screen." Grant notification permission for the Daily Reckoning push.

---

## 9. Build phases

**Phase 0 — Prove the feel (weekend, ~1 day)**
Pure client-side prototype. IndexedDB only, no server, no auth. Capture, list, four exits, full decay rendering. Run it as your only todo system for one week.
*Gate: do you actually open it? Does the decay visual create the pressure you wanted, or is it just annoying? Adjust thresholds before writing any backend.*

**Phase 1 — Make it real (~2–3 days)**
Fastify + SQLite + sync + passphrase auth. Deploy to the VPS with Caddy and systemd. Backups on.

**Phase 2 — Close the capture gap (~2 days)**
PWA install, Web Share Target, desktop global hotkey, `POST /api/tasks` with token for scripting/shortcuts, email-to-capture via a catchall address.
*This is where the app either becomes a habit or doesn't. If capture takes more than 3 seconds, the 24h clock is lying to you.*

**Phase 3 — The forcing function (~2 days)**
Daily Reckoning modal, web push notifications, streak tracking, stats tab.

**Phase 4 — Only if earned**
Contexts, weekly review email, mobile widget.

---

## 10. Risks and honest concerns

- **The decay visual could become wallpaper.** Any fixed visual language stops being felt after ~3 weeks. Mitigation: the *Daily Reckoning* is the real mechanism; decay is the ambient reminder. Don't rely on color alone.

- **You'll stop capturing to protect your RATE.** This is the classic metric-gaming failure — if writing something down starts a clock you might fail, you stop writing things down. Mitigation: make DROPPED a first-class, celebrated exit, and put "tasks captured" next to RATE so a suspiciously low capture count is visible.

- **Not everything fits in 24h and pretending otherwise is a lie.** DECIDED is the honest exit for these, but it must demand a concrete artifact (a date, or a named next action) or it degenerates into a snooze button. Consider hard-requiring a date field on DECIDED.

- **You are building a todo app, which is the classic productive-procrastination trap.** Phase 0 is one day for a reason. Ship the ugly version, use it for a week, and only then build the backend.

- **Sync conflicts on 2 devices are rare but real.** Last-write-wins is fine; just make sure `captured_at` is never overwritten, or the whole premise breaks.

---

## 11. Repo and deploy shape

```
twentyfour/                       github.com/<you>/twentyfour  (public)
  client/
    index.html                    Phase 0 lives entirely here
    manifest.webmanifest          Phase 2
    sw.js                         Phase 2
  server/                         Phase 1
    src/ · package.json
  deploy/
    Caddyfile
    24.service
  .github/workflows/deploy.yml    rsync client + restart service on push to main
  .gitignore                      data/  .env  node_modules/
  README.md · LICENSE (MIT)
```

**Secrets never enter the repo.** `PASSPHRASE`, VAPID keys, and `DB_PATH` live in `/srv/24/server/.env` (mode `600`) on the VPS. `SSH_HOST` / `SSH_USER` / `SSH_KEY` live in GitHub Secrets, using a deploy-only keypair. Give the deploy user a single sudoers line for `systemctl restart 24` rather than blanket sudo.

Because the repo is public, treat the passphrase as the only thing standing between the internet and your list: make it long, and rate-limit `/login` (5 attempts per 15 min per IP) from day one.

Full Caddyfile, systemd unit, and workflow YAML are in `README.md`.

---

## 12. Remaining open questions

1. **Notification channel for the reckoning.** Web push works on installed PWAs, but iOS requires home-screen install and is occasionally flaky. Want an email fallback in Phase 3?
2. **What happens to a DECIDED child on its date?** Options: it appears at 00:00 that day with a fresh 24h clock (simple), or at a time you set. I lean 00:00.
3. **Fossil auto-drop.** Should tasks past ~14 days auto-drop with a note, or always require your hand? I lean requiring your hand — auto-drop is a hidden snooze.
