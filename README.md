# ZAINUXBRAND VPN Panel (menu.sh)

A powerful all-in-one VPN management script for VPS servers. Supports both **SSH-based VPN** (Dropbear + WebSocket + SSL) and **3X-UI Panel** (VLESS / VMess / Trojan + gRPC / WebSocket + TLS) — all managed from a single terminal menu.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Menu Options](#menu-options)
- [3X-UI Auto Install (Option 9)](#3x-ui-auto-install-option-9)
- [Terminal Account Creation (Option 10)](#terminal-account-creation-option-10)
- [Full Uninstall (Option 11)](#full-uninstall-option-11)
- [Fix & Diagnose (Option 12)](#fix--diagnose-option-12)
- [SSH Tunnel Access (for Cloud-Firewalled VPS)](#ssh-tunnel-access-for-cloud-firewalled-vps)
- [Client Setup (DarkTunnel / v2rayNG / etc.)](#client-setup-darktunnel--v2rayng--etc)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Features

| Feature | Details |
|---|---|
| **3X-UI Panel** | Full auto-install with VLESS/VMess/Trojan + gRPC/WS + TLS |
| **SSH VPN** | Dropbear + WebSocket + SSL/TLS tunneling |
| **SSL Certificates** | Auto-generated via acme.sh (Let's Encrypt) |
| **Terminal Account Creation** | Create VLESS/VMess/Trojan accounts without opening browser |
| **Auto Port Detection** | Automatically picks available ports for inbounds |
| **BBR Optimization** | TCP BBR congestion control for speed |
| **Firewall Config** | UFW rules for standard ports |
| **Fix & Diagnose** | Live debugging with 13 diagnostic + fix tools |
| **Full Uninstall** | Complete VPS reset to fresh state |
| **Telegram Bot** | Optional bot for remote account management |
| **Custom SSH Banner** | "ZAINUXBRAND" branded banner on SSH connect |

---

## Requirements

- **VPS**: Ubuntu 20.04 / 22.04 / 24.04 (Debian 11/12 also works)
- **Root access** (run as `root` user)
- **Domain name** pointing to your VPS IP (A record)
- **Open ports**: 22 (SSH), 80 (HTTP/cert), 443 (HTTPS), 8443 (Panel)
- **Minimum RAM**: 512MB (1GB recommended)
- **Python 3** (for xui-helper account creator)

> **Note**: If your VPS provider has a cloud firewall (e.g., UpCloud, Hetzner), make sure ports 80, 443, and 8443 are open in both the VPS firewall AND the provider's dashboard firewall.

---

## Quick Start

```bash
# 1. Login to your VPS as root
ssh root@YOUR_VPS_IP

# 2. Download the script (or upload menu.sh)
wget -O menu.sh https://raw.githubusercontent.com/zainiking8/vps-panel2/main/menu.sh

# 3. Make executable
chmod +x menu.sh

# 4. Run it!
./menu.sh
```

Then select **Option 9** for full automatic install — just enter your domain and everything is set up automatically.

---

## Installation

### Method 1: Direct Download

```bash
wget -O menu.sh https://raw.githubusercontent.com/zainiking8/vps-panel2/main/menu.sh
chmod +x menu.sh
./menu.sh
```

### Method 2: Manual Upload

1. Copy `menu.sh` to your VPS (via SCP, SFTP, or paste into terminal)
2. Run:
```bash
chmod +x menu.sh
./menu.sh
```

> The script **must** be run as `root`. If you're not root, run `sudo -i` first.

---

## Menu Options

| # | Option | Description |
|---|---|---|
| 1 | Auto Install System Components | Installs Dropbear, Nginx, Python, SSL tools, etc. |
| 2 | Add / Change Domain Name | Set your domain (e.g., `sub.example.com`) |
| 3 | Issue SSL Certificate | Manually create Let's Encrypt SSL cert |
| 4 | Manage Accounts (SSH) | Add/Delete/Renew SSH VPN users, set limits |
| 5 | Check Status & Ports | View running services and listening ports |
| 6 | Set / Edit SSH Banner | Customize the "ZAINUXBRAND" connect banner |
| 7 | Fix SSH WS & WS+SSL Connection | Repair broken WebSocket/SSL tunneling |
| 8 | Setup / Manage Telegram Bot | Configure Telegram bot for remote management |
| **9** | **FULL AUTO Install** | **Domain do → 3X-UI + SSH + SSL sab automatic** |
| **10** | **Manage X-UI Accounts** | **Terminal se VLESS/VMess/Trojan accounts banao** |
| **11** | **FULL UNINSTALL** | **VPS fresh reset — sab kuch delete** |
| **12** | **Fix & Diagnose** | **Live issue detection + fix. Press 0 for Auto Fix Everything** |
| 13 | Exit | Quit the panel |

---

## 3X-UI Auto Install (Option 9)

This is the **one-click everything** option. You only need to provide your domain — the script handles the rest.

### What it does automatically:

1. **System update** + package installation
2. **Domain setup** + DNS resolution check
3. **SSH VPN system** (Dropbear + WebSocket + SSL)
4. **3X-UI Panel** installation (from mhsanaei/3x-ui)
5. **Panel credentials** set to: `admin` / `zaini123`
6. **Panel port** set to: `8443`
7. **BBR** congestion control enabled
8. **Firewall** (UFW) configured for required ports
9. **SSL Certificate** auto-created via acme.sh (Let's Encrypt)
10. **Terminal Account Creator** (xui-helper.py) installed

### How to use:

```
Select Option [1-13]: 9

Enter your domain (e.g. sub.example.com): zaini.yourdomain.com
```

That's it! Wait 2-3 minutes. When done, you'll see:

```
====================================================
       FULL AUTO INSTALL COMPLETE!
       (Sirf domain diya, baaki sab khud)
====================================================
 Domain     : zaini.yourdomain.com
 Panel Port : 8443
 Username   : admin
 Password   : zaini123
 Cert Path  : /root/cert/zaini.yourdomain.com/fullchain.pem
 Key Path   : /root/cert/zaini.yourdomain.com/privkey.pem
----------------------------------------------------
AB BAS:
  Option 10 se account banao (VLESS/VMess/Trojan)
  Sirf naam do, link khud ban jayega!
  DarkTunnel me paste -> Connect!
====================================================
```

### Panel Access

- **URL**: `https://YOUR_VPS_IP:8443` (or via SSH tunnel — see below)
- **Username**: `admin`
- **Password**: `zaini123`

> If the panel doesn't open in your browser, your VPS provider's cloud firewall is blocking port 8443. Use the [SSH Tunnel method](#ssh-tunnel-access-for-cloud-firewalled-vps) below.

---

## Terminal Account Creation (Option 10)

Create VPN accounts **directly from the terminal** — no browser needed!

### Available account types:

| # | Protocol | Transport | Security |
|---|---|---|---|
| 1 | VLESS | gRPC | SSL/TLS |
| 2 | VLESS | WebSocket | SSL/TLS |
| 3 | VMess | gRPC | SSL/TLS |
| 4 | VMess | WebSocket | SSL/TLS |
| 5 | Trojan | gRPC | SSL/TLS |
| 6 | Trojan | WebSocket | SSL/TLS |

### Additional sub-options:

| # | Action |
|---|---|
| 7 | List All X-UI Accounts |
| 8 | Delete X-UI Account (by ID) |
| 9 | Re-Configure Panel Access |
| 10 | Back to Main Menu |

### Creating an account (example):

```
Select: 1  (VLESS + gRPC + SSL/TLS)

  Selected: VLESS + gRPC + TLS
  Auto Port: 443

  Account/Remark naam (e.g. user1): myuser
  Expiry days (0=unlimited, default 0): 30
  IP limit (0=unlimited, default 0): 2
  Data limit GB (0=unlimited, default 0): 50
```

Output:

```
=======================================================
  ACCOUNT CREATED BY ZAINUXBRAND
=======================================================
  Protocol  : VLESS + gRPC + TLS
  Domain    : zaini.yourdomain.com
  Port      : 443
  Remark    : myuser
  Expiry    : 30 days
  IP Limit  : 2
  Data Limit: 50.0 GB
-------------------------------------------------------
  CONFIG LINK (DarkTunnel me paste karein):
  vless://a1b2c3d4-...@zaini.yourdomain.com:443?type=grpc&serviceName=tunnel&security=tls&sni=...#myuser
-------------------------------------------------------
  Upar wala link copy karo -> DarkTunnel -> Connect!
=======================================================
```

Just copy the `vless://` link and paste it into your VPN client (DarkTunnel, v2rayNG, etc.).

### Account limits explained:

- **Expiry days**: `0` = never expires. `30` = expires after 30 days.
- **IP limit**: `0` = unlimited devices. `2` = max 2 simultaneous connections.
- **Data limit**: `0` = unlimited data. `50` = 50 GB total download/upload.

---

## Full Uninstall (Option 11)

Completely removes everything installed by this script and resets the VPS to a fresh state.

### What gets removed (10 steps):

1. **3X-UI Panel** — stopped and fully removed
2. **Xray core** — binary and configs deleted
3. **acme.sh** — SSL certificate tool removed
4. **SSL certificates** — `/root/cert/` directory deleted
5. **SSH VPN users** — all created SSH accounts deleted
6. **Dropbear** — uninstalled
7. **Nginx configs** — VPN-related configs removed
8. **Python helper** — `xui-helper.py` removed
9. **Config files** — `/etc/zainuxbrand/` directory deleted
10. **System cleanup** — unused packages autoremoved

> **Warning**: This is irreversible. All accounts, certificates, and configs will be deleted. Use with caution.

---

## Fix & Diagnose (Option 12)

A built-in diagnostic toolkit with 13 tools to detect and fix issues live — without leaving the terminal.

| # | Tool | What it does |
|---|---|---|
| 0 | **AUTO FIX EVERYTHING** | **Automatically fixes DNS, SSH, nginx, panel creds, SSL, and restarts all services** |
| 1 | Restart ALL Services | Restart x-ui, dropbear, nginx, ws-proxy, autokill |
| 2 | Check Listening Ports | `ss -tlnp` filtered for VPN-relevant ports |
| 3 | Check DNS Resolution | Verify domain points to VPS IP |
| 4 | Check SSL Certificate | Show cert subject, dates, issuer |
| 5 | Fix/Re-issue SSL Certificate | Re-create SSL cert via acme.sh (standalone mode) |
| 6 | Fix Panel Credentials | Reset panel to `admin` / `zaini123` |
| 7 | Fix Panel Port | Change panel port to `8443` |
| 8 | Check Firewall Rules | Show UFW status + cloud firewall reminder |
| 9 | View x-ui Logs | Last 30 lines of x-ui journal logs |
| 10 | Fix Nginx Config | Regenerate nginx VPN config (with backup) |
| 11 | Check VPS IP + Connectivity | Show public IP and internet status |
| 12 | Full System Diagnostic Report | Complete report: OS, services, ports, SSL, DNS, firewall |
| 13 | Back to Main Menu | Return to main menu |

### When to use what:

- **Kuch bhi sahi nahi chal raha?** → **Option 0 (AUTO FIX EVERYTHING)** sabse pehle try karein
- **Panel not opening?** → Try Option 1 (restart), then Option 7 (fix port), then Option 6 (fix credentials)
- **Can't connect to VPN?** → Try Option 1 (restart all), Option 2 (check ports), Option 3 (check DNS)
- **SSL errors?** → Try Option 4 (check cert), then Option 5 (re-issue cert)
- **Everything broken?** → Option 12 (full diagnostic report) to see the complete picture
- **Rate limit error?** → Option 5 automatically switches to ZeroSSL if Let's Encrypt rate limit hits

---

## SSH Tunnel Access (for Cloud-Firewalled VPS)

If your VPS provider (e.g., UpCloud) blocks port 8443, you can access the 3X-UI panel through an SSH tunnel.

### Using Termius (recommended):

1. Open **Termius** app
2. Go to **Port Forwarding** → New
3. Type: **Local**
4. Local: `localhost:8443`
5. Remote: `localhost:8443`
6. Connect to your VPS

Then open in browser: `https://localhost:8443`

### Using terminal (macOS/Linux):

```bash
ssh -L 8443:localhost:8443 root@YOUR_VPS_IP
```

Then open: `https://localhost:8443`

> You'll see a browser SSL warning (self-signed cert on localhost) — click "Advanced" → "Proceed anyway". This is normal.

---

## Client Setup (DarkTunnel / v2rayNG / etc.)

### DarkTunnel (iOS/Android):

1. Open DarkTunnel app
2. Tap **+** → **Import from Clipboard**
3. Copy the `vless://` link from Option 10 output
4. Paste and save
5. Tap connect

### v2rayNG (Android):

1. Open v2rayNG
2. Tap **+** (top right) → **Import from Clipboard**
3. Copy the link → paste
4. Select the config → tap **V** to connect

### Required settings (auto-configured by this script):

- **Address**: Your domain (e.g., `zaini.yourdomain.com`)
- **Port**: 443 (or auto-selected port)
- **UUID**: Auto-generated
- **Security**: TLS
- **SNI**: Your domain
- **Transport**: gRPC (serviceName: `tunnel`) or WebSocket (path: `/tunnel`)
- **Fingerprint**: chrome

---

## Troubleshooting

### wget / curl / apt not working (can't download anything)

**Cause**: DNS issue, IPv6 problem, no internet, or broken apt sources.

**Fix**:

1. **Check internet first:**
```bash
ping -c 3 8.8.8.8
```
If no reply, VPS has no internet — contact your provider.

2. **Check DNS resolution:**
```bash
nslookup raw.githubusercontent.com
```
If DNS fails, fix nameservers:
```bash
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
```

3. **Disable IPv6** (common problem on some VPS):
```bash
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p
```
Then try `wget` again.

4. **apt update failing:**
```bash
apt-get clean
apt-get update -o Acquire::ForceIPv4=true
```

5. **If nothing works**, manually upload `menu.sh` via SFTP/SCP or copy-paste.

### Panel won't open in browser

**Cause**: Cloud provider firewall blocking port 8443.

**Fix**:
1. Open port 8443 in your VPS provider's dashboard firewall
2. OR use [SSH Tunnel](#ssh-tunnel-access-for-cloud-firewalled-vps) method
3. OR run Option 12 → Option 7 to confirm port is 8443

### VPN connection fails

**Cause**: DNS not pointing to VPS, or SSL cert missing/invalid.

**Fix**:
1. Option 12 → Option 3: Check DNS resolution
2. Option 12 → Option 4: Check SSL cert
3. Option 12 → Option 5: Re-issue SSL if needed
4. Option 12 → Option 1: Restart all services

### "Panel login fail" in terminal account creation

**Cause**: Wrong credentials or panel not running.

**Fix**:
1. Option 12 → Option 6: Reset credentials to `admin`/`zaini123`
2. Option 12 → Option 1: Restart all services
3. Option 12 → Option 9: Check x-ui logs

### SSL certificate creation fails

**Cause**: Domain DNS not pointing to VPS, or port 80 blocked.

**Fix**:
1. Verify domain A record points to your VPS IP
2. Make sure port 80 is open in firewall
3. Option 12 → Option 5: Re-issue with `--force` flag

### x-ui service won't start

**Fix**:
1. Option 12 → Option 9: Check logs for error messages
2. Option 12 → Option 1: Restart all services
3. If still failing, re-install: Option 11 (uninstall) → Option 9 (reinstall)

---

## FAQ

### Q: Do I need to open the browser/Chrome to create accounts?

**No!** Option 10 lets you create VLESS/VMess/Trojan accounts entirely from the terminal. Just select the protocol, enter a name, and the config link is generated automatically.

### Q: What's the default panel username and password?

- **Username**: `admin`
- **Password**: `zaini123`
- **Port**: `8443`

You can reset these anytime with Option 12 → Option 6.

### Q: Can I change the UUID or password in accounts?

The UUID and password are auto-generated for security. You can't set a custom UUID, but the **remark/name** field lets you label each account. The auto-generated link is all you need to connect.

### Q: Does VLESS support a custom banner like SSH?

No. VLESS/VMess/Trojan protocols don't support server-side banners. You can only customize the **remark/profile name** which appears in your client app.

### Q: Can I use both SSH VPN and 3X-UI at the same time?

Yes! They run on different ports and don't conflict. Option 9 installs both automatically.

### Q: What protocols are supported?

- **VLESS** + gRPC + TLS
- **VLESS** + WebSocket + TLS
- **VMess** + gRPC + TLS
- **VMess** + WebSocket + TLS
- **Trojan** + gRPC + TLS
- **Trojan** + WebSocket + TLS

All use **SSL/TLS** (not Reality).

### Q: How do I update the 3X-UI panel?

```bash
x-ui update
```

Or through the panel web interface → Panel Settings → Update.

### Q: Is this script safe to use?

Yes. The script only installs standard open-source tools (3X-UI, Xray, Dropbear, Nginx, acme.sh). No data is sent to third parties. All credentials are stored locally on your VPS.

### Q: What if I mess something up?

1. Use **Option 12 (Fix & Diagnose)** to identify and fix issues
2. If unfixable, use **Option 11 (Full Uninstall)** to reset everything
3. Then **Option 9 (Full Auto Install)** to start fresh

---

## Technical Details

### File Locations

| File | Purpose |
|---|---|
| `/workspace/menu.sh` | Main script |
| `/usr/local/x-ui/` | 3X-UI panel installation |
| `/etc/x-ui/x-ui.db` | 3X-UI database (inbounds, settings) |
| `/usr/local/bin/xui-helper.py` | Terminal account creator (Python) |
| `/etc/zainuxbrand/xui.conf` | Panel config (credentials, domain, cert paths) |
| `/etc/zainuxbrand/domain.conf` | Stored domain name |
| `/root/cert/DOMAIN/fullchain.pem` | SSL certificate |
| `/root/cert/DOMAIN/privkey.pem` | SSL private key |
| `/root/.acme.sh/` | acme.sh installation |
| `/etc/nginx/conf.d/vpn.conf` | Nginx VPN config |

### Panel Config Format (`/etc/zainuxbrand/xui.conf`)

```ini
PANEL_USER="admin"
PANEL_PASS="zaini123"
PANEL_PORT="8443"
PANEL_DOMAIN="your.domain.com"
CERT_PATH="/root/cert/your.domain.com/fullchain.pem"
KEY_PATH="/root/cert/your.domain.com/privkey.pem"
```

### Required Ports

| Port | Service |
|---|---|
| 22 | SSH (Dropbear) |
| 80 | HTTP / SSL cert verification |
| 443 | HTTPS / VLESS inbound |
| 109 | SSH alternative (Dropbear) |
| 447 | SSH alternative (Dropbear) |
| 8443 | 3X-UI Panel |

---

## Credits

- **3X-UI Panel**: [mhsanaei/3x-ui](https://github.com/mhsanaei/3x-ui)
- **Xray Core**: [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- **acme.sh**: [acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh)
- **Script**: ZAINUXBRAND

---

## License

This script is provided as-is for educational and personal use. Use responsibly and in accordance with your local laws.
