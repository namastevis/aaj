# 24h

A todo app where the only thing that matters is how long a task has been sitting there.

Live at **[24h.namastevis.in](https://24h.namastevis.in)**

---

## The idea

Every task you write down gets **resolved within 24 hours of capture**. Resolved does not mean done — there are four exits:

| Exit | Meaning | Key |
|---|---|---|
| **Done** | You did it | `D` |
| **Delegated** | Someone else owns it now (requires a name) | `G` |
| **Decided** | You know what this is and when it happens (requires a date) | `S` |
| **Dropped** | You've decided it doesn't matter | `X` |

The clock starts the moment you type the task and cannot be edited. Tasks past 24h visibly decay — they desaturate, redden, pick up grain, and pin themselves to the top of the list. Past 96h they fall into the **Fossil Bed** with one button: drop them all.

There is no snooze, no priority, no due dates, no someday list. Those are the escape hatches that let a task sit for six weeks, and this app is specifically about not having them.

### The two numbers

- **DEBT** — open tasks past 24h. Target: 0.
- **RATE** — % of the last 7 days' tasks resolved within 24h. Target: >90%.

`CAPTURED 7d` sits next to RATE on purpose: if the rate looks great but capture has collapsed, you're gaming your own metric.

---

## Status

**Phase 0** — a single self-contained `client/index.html`. No build step, no server, no accounts. Data lives in `localStorage` on the device, with JSON export/import.

```bash
cd client && python3 -m http.server 8000   # then open http://localhost:8000
```

Or just open `client/index.html` directly. Click **Load demo data** to see all four decay stages at once.

### Layout

```
client/     the whole app — index.html, manifest, icon
deploy/     Caddyfile, systemd unit, one-time VPS setup script
docs/       SPEC.md — the full product and technical spec
.github/    deploy workflow (rsync client/ to the VPS on push to main)
```

Roadmap:

- [x] Phase 0 — client-only prototype, decay rendering, four exits, reckoning
- [ ] Phase 1 — Fastify + SQLite backend, sync, passphrase auth, VPS deploy
- [ ] Phase 2 — PWA install, Web Share Target, capture API, desktop hotkey
- [ ] Phase 3 — web push for the nightly reckoning, streaks, stats tab

---

## Keyboard

| | |
|---|---|
| `/` | jump to capture |
| `Enter` | capture |
| `↑` `↓` / `k` `j` | select |
| `D` `G` `S` `X` | resolve selected |
| `Esc` | leave the input |

---

## Deploying to the VPS

**Step-by-step Hostinger walkthrough: [`docs/HOSTINGER.md`](docs/HOSTINGER.md).** The reference configs below are what that guide installs.

DNS: `A` record for `24h` → your VPS IP.

### Caddy — `/etc/caddy/Caddyfile`

```
24h.namastevis.in {
	encode gzip

	handle /api/* {
		reverse_proxy localhost:8080
	}
	handle {
		root * /srv/24h/client
		try_files {path} /index.html
		file_server
	}
}
```

TLS certs are fetched automatically on the first request. Nothing else to configure.

### systemd (Phase 1, once there's a server) — `/etc/systemd/system/24h.service`

```ini
[Unit]
Description=24h
After=network.target

[Service]
User=app24h
WorkingDirectory=/srv/24h/server
EnvironmentFile=/srv/24h/server/.env
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### One-time server setup

```bash
sudo useradd -r -s /usr/sbin/nologin app24h
sudo mkdir -p /srv/24h/{client,server,data}
sudo chown -R app24h: /srv/24h
sudo systemctl enable --now caddy
```

### GitHub Actions

`.github/workflows/deploy.yml` rsyncs `client/` to `/srv/24h/client` on every push to `main`, then smoke-tests the live URL.

Repo secrets needed under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `SSH_HOST` | VPS IP or hostname |
| `SSH_USER` | deploy user on the VPS |
| `SSH_KEY` | private half of a **deploy-only** ed25519 keypair |

```bash
ssh-keygen -t ed25519 -f ~/.ssh/24h_deploy -C "24h deploy" -N ""
ssh-copy-id -i ~/.ssh/24h_deploy.pub user@vps     # public half onto the box
pbcopy < ~/.ssh/24h_deploy                        # private half into SSH_KEY
```

Give that user a narrow sudoers entry for `systemctl restart 24h` rather than full sudo.

The deploy job is gated on a repo **variable** `DEPLOY_ENABLED = true` (Settings → Secrets and variables → Actions → Variables). Until you set it, pushes skip deployment and stay green — so you can commit freely before the VPS exists.

### Backups (Phase 1)

```
0 3 * * * sqlite3 /srv/24h/data/24h.db ".backup '/srv/24h/data/bk-$(date +\%F).db'" && find /srv/24h/data -name 'bk-*.db' -mtime +14 -delete
```

---

## Open-source notes

This repo is public but built for one person — there's no multi-user support and no self-host documentation beyond the above. Nothing personal is committed: the passphrase, VAPID keys, and DB path all live in `/srv/24h/server/.env` on the box (mode `600`) and in GitHub Secrets. `data/` and `.env` are gitignored.

## License

MIT
