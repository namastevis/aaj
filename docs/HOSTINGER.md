# Deploying 24h on a Hostinger VPS

End state: `https://24h.namastevis.in` serves `client/`, and every push to `main` redeploys it automatically.

Phase 0 is entirely static, so nothing runs on the box except Caddy. Budget about 30 minutes.

---

## 0. Before you start — pick the right OS image

This matters more than anything else here. In hPanel go to **VPS → your server → Settings → OS & Panel**.

Use a **plain Ubuntu 24.04 LTS** image. Do **not** pick an image bundled with CyberPanel, Plesk, cPanel, or CloudPanel — those take ownership of ports 80/443 and their own nginx/OpenLiteSpeed, which will fight Caddy for the TLS certificate and you'll spend an evening debugging it.

If your VPS already has a panel installed, reinstall the OS now while the box is empty: **Settings → OS & Panel → Change OS → Plain OS → Ubuntu 24.04**. This wipes the server.

---

## 1. Point DNS at the VPS

Get the IP from **VPS → your server → Overview** (labelled *IP address*).

Then **Domains → namastevis.in → DNS / Nameservers**, and **Add record**:

| Field | Value |
|---|---|
| Type | `A` |
| Name | `24h` — just that, not the full hostname |
| Points to | your VPS IP |
| TTL | `300` |

DNS editing in hPanel only works if the domain is on Hostinger's nameservers. If you moved it to Cloudflare or elsewhere, add the record there instead.

Do this first — Caddy can't get a TLS certificate until the name resolves. Check from your laptop:

```bash
dig 24h.namastevis.in +short     # should print your VPS IP
```

Propagation is usually a minute or two at TTL 300, occasionally longer.

---

## 2. Open the firewall

Hostinger has its own firewall in front of the box, separate from `ufw` inside it. **VPS → your server → Firewall**. If a ruleset is active, make sure **22 (SSH)**, **80 (HTTP)** and **443 (HTTPS)** are accepted. Port 80 is not optional — Let's Encrypt uses it for the HTTP-01 challenge.

---

## 3. Get a shell

Easiest: **VPS → your server → Browser terminal**. It opens an SSH session in a new tab, already logged in as root, nothing to install.

From your own terminal instead:

```bash
ssh root@<VPS_IP>
```

The root password is under **VPS → Manage → Root password** if you need to set it. Better: add your public key under **VPS → your server → Settings → SSH keys → + SSH key**, paste the contents of `~/.ssh/id_ed25519.pub`, save — then password login isn't needed at all.

---

## 4. Create a deploy user and lock the box down

Working as root over SSH is how servers get owned. Run this once, as root:

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
```

**Open a second terminal and confirm `ssh deploy@<VPS_IP>` works before continuing.** If you disable root login while locked out of the deploy account, the browser terminal is your only way back in.

Once that's verified:

```bash
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'            /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
```

---

## 5. Install Caddy and lay out the directories

As `deploy`:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/namastevis/24h.git
cd 24h
./deploy/setup.sh
```

That script installs Caddy from its official apt repo, creates `/srv/24h/{client,server,data}`, copies the Caddyfile into `/etc/caddy/`, and enables `ufw` for 22/80/443.

Then put something at the document root so the first request succeeds:

```bash
sudo rsync -a ~/24h/client/ /srv/24h/client/
sudo systemctl reload caddy
```

Visit **https://24h.namastevis.in**. Caddy fetches the certificate on that first request — give it a few seconds. The app should load and you can hit *Load demo data* right there.

If it doesn't: `sudo journalctl -u caddy -n 50 --no-pager` tells you why, and it's almost always DNS not yet resolving or port 80 blocked upstream.

---

## 6. Wire up automatic deploys

On your **laptop**, make a keypair used only by GitHub Actions:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/24h_deploy -C "24h deploy" -N ""
ssh-copy-id -i ~/.ssh/24h_deploy.pub deploy@<VPS_IP>
```

On the **VPS**, let that user restart Caddy without a password prompt, and nothing else:

```bash
echo 'deploy ALL=(ALL) NOPASSWD: /bin/systemctl reload caddy, /bin/systemctl restart 24h' \
  | sudo tee /etc/sudoers.d/24h
sudo chmod 440 /etc/sudoers.d/24h
sudo chown -R deploy:deploy /srv/24h/client
```

In **GitHub → your repo → Settings → Secrets and variables → Actions**:

*Secrets tab:*

| Name | Value |
|---|---|
| `SSH_HOST` | your VPS IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | full contents of `~/.ssh/24h_deploy` (the private one, including the BEGIN/END lines) |

*Variables tab:*

| Name | Value |
|---|---|
| `DEPLOY_ENABLED` | `true` |

Now push anything to `main`. The workflow rsyncs `client/` to `/srv/24h/client` and curls the live URL to confirm it's up.

---

## 7. Install it on your phone

Open `https://24h.namastevis.in` in Safari or Chrome on your phone → **Share → Add to Home Screen**. It launches fullscreen with no browser chrome, and the manifest is already in the repo.

Remember Phase 0 stores everything in `localStorage` **per device** — your phone and laptop keep separate lists until Phase 1 adds the sync server. Use **Export JSON** if you need to move data across in the meantime.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Could not resolve host` / cert fails | DNS hasn't propagated. `dig 24h.namastevis.in +short` must return your IP. |
| Connection times out on 443 | Hostinger's panel firewall, not `ufw`. Check **VPS → Firewall**. |
| Caddy won't bind :80 | A control panel's web server is already there. `sudo ss -tlnp \| grep :80` will name it. |
| Action fails at rsync | `SSH_KEY` is usually pasted without its trailing newline, or the public half never made it to `authorized_keys`. |
| Page doesn't update after deploy | Hard-refresh. The Caddyfile sends `Cache-Control: no-cache`, but an installed PWA can hold the old shell. |

---

## Cost note

For Phase 0 the VPS is doing nothing a $0 static host couldn't do. Keep it if you're committed to Phase 1's sync server — that's when the box earns its keep. If after a week of using the app you don't want the backend, the whole thing can move to any static host and you can drop the VPS.

---

Sources: [Hostinger VPS SSH](https://www.hostinger.com/support/5723772-how-to-connect-to-your-vps-via-ssh-at-hostinger/) · [SSH keys on VPS](https://www.hostinger.com/support/4792364-how-to-use-ssh-keys-at-hostinger-vps/) · [DNS zone editor](https://www.hostinger.com/support/how-to-use-hostingers-dns-zone-editor/) · [Managing A records](https://www.hostinger.com/support/4468886-how-to-manage-a-records-at-hostinger/)
