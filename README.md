# 24

A todo app where the only thing that matters is how long a task has been sitting there.

Live at **[24.namastevis.in](https://24.namastevis.in)**

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

**Phase 0** — a single self-contained `index.html`. No build step, no server, no accounts. Data lives in `localStorage` on the device, with JSON export/import.

Running it: open `index.html` in a browser, or `python3 -m http.server` in this directory. Click **Load demo data** to see all four decay stages at once.

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

DNS: `A` record for `24` → your VPS IP.

### Caddy — `/etc/caddy/Caddyfile`

```
24.namastevis.in {
	encode gzip

	handle /api/* {
		reverse_proxy localhost:8080
	}
	handle {
		root * /srv/24/client
		try_files {path} /index.html
		file_server
	}
}
```

TLS certs are fetched automatically on the first request. Nothing else to configure.

### systemd (Phase 1, once there's a server) — `/etc/systemd/system/24.service`

```ini
[Unit]
Description=24
After=network.target

[Service]
User=app24
WorkingDirectory=/srv/24/server
EnvironmentFile=/srv/24/server/.env
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### One-time server setup

```bash
sudo useradd -r -s /usr/sbin/nologin app24
sudo mkdir -p /srv/24/{client,server,data}
sudo chown -R app24: /srv/24
sudo systemctl enable --now caddy
```

### GitHub Actions — `.github/workflows/deploy.yml`

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Add SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.SSH_HOST }} >> ~/.ssh/known_hosts

      - name: Rsync client
        run: |
          rsync -az --delete \
            -e "ssh -i ~/.ssh/id_ed25519" \
            ./client/ ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}:/srv/24/client/

      # Phase 1+: build and ship the server, then
      # ssh ... 'cd /srv/24/server && npm ci --omit=dev && sudo systemctl restart 24'
```

Repo secrets needed: `SSH_HOST`, `SSH_USER`, `SSH_KEY` (a deploy-only private key). Give the deploy user a narrow sudoers entry for `systemctl restart 24` rather than full sudo.

### Backups (Phase 1)

```
0 3 * * * sqlite3 /srv/24/data/24.db ".backup '/srv/24/data/bk-$(date +\%F).db'" && find /srv/24/data -name 'bk-*.db' -mtime +14 -delete
```

---

## Open-source notes

This repo is public but built for one person — there's no multi-user support and no self-host documentation beyond the above. Nothing personal is committed: the passphrase, VAPID keys, and DB path all live in `/srv/24/server/.env` on the box (mode `600`) and in GitHub Secrets. `data/` and `.env` are gitignored.

## License

MIT
