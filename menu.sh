#!/bin/bash

# ==============================================================================
# Script Name   : ZAINU x BRAND VPN Panel (Dynamic Domain Supported)
# Custom Path   : /zainuxbrand
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="ZAINUXBRAND VPN Panel"
BANNER_FILE="/etc/issue.net"
CUSTOM_PATH="/zainuxbrand"
DOMAIN_FILE="/etc/zainuxbrand/domain.conf"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Yeh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
   exit 1
fi

# Create global 'menu' command so user can type 'menu' instead of './menu.sh'
SCRIPT_PATH=$(realpath "$0" 2>/dev/null || echo "$0")
if [[ -f "$SCRIPT_PATH" ]]; then
    if [[ ! -e /usr/local/bin/menu ]]; then
        ln -sf "$SCRIPT_PATH" /usr/local/bin/menu 2>/dev/null || cp "$SCRIPT_PATH" /usr/local/bin/menu
    fi
    if [[ ! -e /usr/bin/menu ]]; then
        ln -sf /usr/local/bin/menu /usr/bin/menu 2>/dev/null
    fi
fi

# Robust package installer with retry
ensure_package() {
    local pkg="$1"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        return 0
    fi
    echo -e "${YELLOW}[INSTALL] $pkg install ho raha hai...${NC}"
    apt-get update -y >/dev/null 2>&1 || true
    if apt-get install -y "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] $pkg install ho gaya.${NC}"
        return 0
    fi
    # Retry with fix-missing
    apt-get update -y --fix-missing >/dev/null 2>&1 || true
    if apt-get install -y --fix-broken "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] $pkg install ho gaya (retry).${NC}"
        return 0
    fi
    echo -e "${RED}[ERROR] $pkg install nahi ho saka!${NC}"
    return 1
}

# Ensure all base packages exist (called by every critical path)
ensure_base_packages() {
    local pkgs=("curl" "wget" "socat" "dnsutils" "jq" "openssl" "nginx" "dropbear" "openssh-server" "certbot" "python3" "python3-pip" "lsof" "iptables" "net-tools" "unzip" "tar")
    local missing=()
    for p in "${pkgs[@]}"; do
        if ! dpkg -l "$p" 2>/dev/null | grep -q "^ii"; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[AUTO-INSTALL] Yeh packages missing hain: ${missing[*]}${NC}"
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends "${missing[@]}" >/dev/null 2>&1 || {
            echo -e "${YELLOW}[RETRY] Fix-broken ke sath install kar rahe hain...${NC}"
            apt-get --fix-broken install -y >/dev/null 2>&1 || true
            apt-get install -y --no-install-recommends "${missing[@]}" >/dev/null 2>&1 || true
        }
    fi
    # Final verification
    local still_missing=()
    for p in "${pkgs[@]}"; do
        if ! dpkg -l "$p" 2>/dev/null | grep -q "^ii"; then
            still_missing+=("$p")
        fi
    done
    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo -e "${RED}[ERROR] In packages ko install nahi kar sake: ${still_missing[*]}${NC}"
        echo -e "${YELLOW}Try karein manually: apt-get update && apt-get install -y ${still_missing[*]}${NC}"
        return 1
    fi
    echo -e "${GREEN}[OK] Sab base packages available hain.${NC}"
    return 0
}

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        cat "$DOMAIN_FILE" | tr -d '\r\n'
    else
        echo "No Domain Set"
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

fix_dropbear_core() {
    # CRITICAL: Dropbear package must exist
    if ! dpkg -l dropbear 2>/dev/null | grep -q "^ii"; then
        echo -e "${YELLOW}[INSTALL] Dropbear package missing hai. Install kar rahe hain...${NC}"
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y dropbear >/dev/null 2>&1 || {
            echo -e "${RED}[ERROR] Dropbear install nahi ho saka!${NC}"
            return 1
        }
    fi

    mkdir -p /etc/dropbear
    chmod 700 /etc/dropbear

    # Generate host keys (force regenerate if missing/corrupt)
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key &>/dev/null || true
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key &>/dev/null || true
    dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key &>/dev/null || true

    chmod 600 /etc/dropbear/*_host_key 2>/dev/null

    # Remove broken override directory to prevent crashes
    rm -rf /etc/systemd/system/dropbear.service.d

    # CRITICAL: Use ports 109 & 447 for Dropbear (SSH VPN)
    # Leave port 22 for OpenSSH so admin never gets locked out!
    cat << 'DB_CONF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 447 -b /etc/issue.net"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DB_CONF

    # Ensure OpenSSH is always available on port 22 as safety net
    if ! dpkg -l openssh-server 2>/dev/null | grep -q "^ii"; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y openssh-server >/dev/null 2>&1 || true
    fi
    if [[ -f /etc/ssh/sshd_config ]]; then
        sed -i 's/^#*Port .*/Port 22/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    ssh-keygen -A 2>/dev/null || true
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable dropbear
    systemctl restart dropbear
    sleep 1
    # Verify dropbear is listening
    if ss -tlnp | grep -q ':109 '; then
        echo -e "${GREEN}[OK] Dropbear port 109 pe chal raha hai.${NC}"
    else
        echo -e "${YELLOW}[WARNING] Dropbear start nahi hua. Status check karein: systemctl status dropbear${NC}"
    fi
}

install_python_tracker() {
    cat << 'PY_EOF' > /usr/local/bin/autokill.py
import os
import sys
import time
import subprocess
import re

USER_DIR = "/etc/zainuxbrand/users"
LOG_FILE = "/var/log/autokill.log"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception:
        pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\n" + f.read()
        except Exception:
            pass
    return raw

def get_active_users_and_pids(raw_logs):
    user_pids = {}
    try:
        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        for line in ps_out.splitlines():
            if "dropbear" in line and "grep" not in line:
                parts = line.split()
                if len(parts) > 1:
                    pid = parts[1]
                    matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
                    if matches:
                        last_line = matches[-1]
                        m = re.search(r"for \x27(\w+)\x27", last_line)
                        if not m:
                            m = re.search(r"for (\w+)", last_line)
                        if m:
                            uname = m.group(1)
                            if uname not in user_pids:
                                user_pids[uname] = []
                            user_pids[uname].append(pid)
    except Exception:
        pass
    return user_pids

def get_pid_io_bytes(pid):
    io_file = f"/proc/{pid}/io"
    total_bytes = 0
    if os.path.exists(io_file):
        try:
            with open(io_file, "r") as f:
                for line in f:
                    if line.startswith("rchar:") or line.startswith("wchar:"):
                        total_bytes += int(line.split(":")[1].strip())
        except Exception:
            pass
    return total_bytes

last_pid_bytes = {}

while True:
    try:
        raw_logs = get_auth_logs()
        user_pids_map = get_active_users_and_pids(raw_logs)

        if os.path.exists(USER_DIR):
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue

                uname = fname[:-5]
                conf_path = os.path.join(USER_DIR, fname)

                ip_limit = 0
                gb_limit = "Unlimited"
                used_mb = 0.0

                with open(conf_path, "r") as f:
                    lines = f.readlines()

                for line in lines:
                    if line.startswith("IP_LIMIT="):
                        try: ip_limit = int(line.strip().split("=")[1])
                        except Exception: pass
                    elif line.startswith("GB_LIMIT="):
                        gb_limit = line.strip().split("=")[1]
                    elif line.startswith("USED_MB="):
                        try: used_mb = float(line.strip().split("=")[1])
                        except Exception: pass

                active_pids = user_pids_map.get(uname, [])

                for pid in active_pids:
                    current_b = get_pid_io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = current_b - last_pid_bytes[pid]
                        if diff > 0:
                            used_mb += (diff / (1024.0 * 1024.0))
                    last_pid_bytes[pid] = current_b

                new_lines = []
                for line in lines:
                    if line.startswith("USED_MB="):
                        new_lines.append(f"USED_MB={used_mb:.2f}\n")
                    else:
                        new_lines.append(line)
                with open(conf_path, "w") as f:
                    f.writelines(new_lines)

                if gb_limit != "Unlimited":
                    try:
                        max_mb = float(gb_limit) * 1024.0
                        if used_mb >= max_mb:
                            subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            for pid in active_pids:
                                subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass

                if ip_limit > 0 and len(active_pids) > ip_limit:
                    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for pid in active_pids:
                        subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    except Exception:
        pass

    time.sleep(3)
PY_EOF
    chmod +x /usr/local/bin/autokill.py

    cat << 'SVC_EOF' > /etc/systemd/system/autokill.service
[Unit]
Description=zainuxbrand Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable autokill
    systemctl restart autokill
}

install_tgbot_script() {
    cat << 'PY_EOF' > /usr/local/bin/tgbot.py
import os
import re
import json
import asyncio
import subprocess
from datetime import datetime, timedelta

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, ContextTypes, filters,
)

PANEL_NAME = "zainuxbrand VPN Panel"
CONFIG_FILE = "/etc/zainuxbrand/tgbot/config.json"
ADMINS_FILE = "/etc/zainuxbrand/tgbot/admins.json"
USERS_DIR = "/etc/zainuxbrand/users"
DOMAIN_FILE = "/etc/zainuxbrand/domain.conf"
BANNER_FILE = "/etc/issue.net"

NGINX_TEMPLATE = """server {{
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name {dom} _;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /zainuxbrand {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}

server {{
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name {dom} _;

    ssl_certificate /etc/letsencrypt/live/{dom}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{dom}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /zainuxbrand {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}
"""

FLOWS = {
    "add_user": [
        ("username", "\U0001F464 Username enter karein:"),
        ("password", "\U0001F511 Password enter karein:"),
        ("days", "\U0001F4C5 Expiry days enter karein (e.g. 30):"),
        ("ip_limit", "\U0001F310 Max IP Limit enter karein (e.g. 1):"),
        ("gb_limit", "\U0001F4BE Data Limit GB enter karein (e.g. 5, ya Unlimited):"),
    ],
    "del_user": [("username", "\U0001F464 Delete karne ke liye Username enter karein:")],
    "renew_user": [
        ("username", "\U0001F464 Username enter karein jise renew karna hai:"),
        ("days", "\U0001F4C5 Kitne additional days add karne hain?"),
    ],
    "ip_limit": [
        ("username", "\U0001F464 Username enter karein:"),
        ("value", "\U0001F310 Naya IP Limit enter karein:"),
    ],
    "gb_limit": [
        ("username", "\U0001F464 Username enter karein:"),
        ("value", "\U0001F4BE Naya GB Limit enter karein:"),
    ],
    "domain": [("value", "\U0001F30D Naya domain enter karein (e.g. sub.example.com):")],
    "banner": [("value", "\U0001F4E2 Naya SSH banner text bhejein:")],
    "add_admin": [("value", "\U0001F451 Naye Admin ka Telegram User ID enter karein:")],
    "remove_admin": [("value", "\U0001F5D1 Remove karne ke liye Admin ka Telegram User ID enter karein:")],
}

def load_config():
    with open(CONFIG_FILE) as f:
        return json.load(f)

def load_admins():
    if not os.path.exists(ADMINS_FILE):
        return []
    with open(ADMINS_FILE) as f:
        return json.load(f)

def save_admins(admins):
    with open(ADMINS_FILE, "w") as f:
        json.dump(admins, f)

def is_admin(uid):
    return uid in load_admins()

def is_super(uid):
    cfg = load_config()
    return uid == cfg.get("super_admin")

def sh(cmd_list, input_data=None):
    return subprocess.run(cmd_list, capture_output=True, text=True, input=input_data)

def run(cmd_str):
    return subprocess.run(cmd_str, shell=True, capture_output=True, text=True)

def get_domain():
    if os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE) as f:
            d = f.read().strip()
            return d if d else "No Domain Set"
    return "No Domain Set"

def apply_nginx_config():
    dom = get_domain()
    if dom == "No Domain Set":
        return
    os.makedirs("/etc/nginx/conf.d", exist_ok=True)
    with open("/etc/nginx/conf.d/vpn.conf", "w") as f:
        f.write(NGINX_TEMPLATE.format(dom=dom))
    sh(["rm", "-f", "/etc/nginx/sites-enabled/default"])
    sh(["systemctl", "restart", "nginx"])

def valid_username(u):
    return re.match(r"^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$", u) is not None

def add_user(username, password, days, ip_limit, gb_limit):
    if not valid_username(username):
        return False, "Invalid username (letter se start, sirf a-z 0-9 _ - allowed)."
    try:
        exp_date = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False, "Invalid days value."
    r = sh(["useradd", "-M", "-s", "/bin/bash", "-e", exp_date, username])
    if r.returncode != 0:
        return False, (r.stderr.strip() or "User create failed (already exists?)")
    sh(["chpasswd"], input_data=f"{username}:{password}\n")
    os.makedirs(USERS_DIR, exist_ok=True)
    with open(f"{USERS_DIR}/{username}.conf", "w") as f:
        f.write(f"IP_LIMIT={ip_limit}\nGB_LIMIT={gb_limit}\nUSED_MB=0.0\n")
    return True, exp_date

def delete_user(username):
    sh(["userdel", "-f", username])
    try:
        os.remove(f"{USERS_DIR}/{username}.conf")
    except FileNotFoundError:
        pass

def renew_user(username, days):
    r = sh(["id", username])
    if r.returncode != 0:
        return False
    try:
        new_exp = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False
    sh(["usermod", "-e", new_exp, username])
    sh(["passwd", "-u", username])
    return True

def update_conf_field(username, field, value):
    path = f"{USERS_DIR}/{username}.conf"
    if not os.path.exists(path):
        return False
    lines = open(path).readlines()
    new_lines = []
    found = False
    for line in lines:
        if line.startswith(f"{field}="):
            new_lines.append(f"{field}={value}\n")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{field}={value}\n")
    with open(path, "w") as f:
        f.writelines(new_lines)
    sh(["passwd", "-u", username])
    return True

def list_users_text():
    if not os.path.isdir(USERS_DIR):
        return "Koi user nahi mila."
    entries = []
    for fname in sorted(os.listdir(USERS_DIR)):
        if not fname.endswith(".conf"):
            continue
        uname = fname[:-5]
        data = {}
        for l in open(f"{USERS_DIR}/{fname}"):
            if "=" in l:
                k, v = l.strip().split("=", 1)
                data[k] = v
        exists = sh(["id", uname]).returncode == 0
        status = "Deleted"
        if exists:
            p = sh(["passwd", "-S", uname])
            status = "LOCKED" if " L " in f" {p.stdout} " else "Active"
        used_mb = 0.0
        try:
            used_mb = float(data.get("USED_MB", "0") or 0)
        except ValueError:
            pass
        used_gb = round(used_mb / 1024, 2)
        entries.append(
            f"\U0001F464 {uname} | IP:{data.get('IP_LIMIT', '?')} | "
            f"Used:{used_gb}GB / {data.get('GB_LIMIT', '?')}GB | {status}"
        )
    return "\n".join(entries) if entries else "Koi user nahi mila."

def connected_ips_text():
    r = sh(["ss", "-tnp"])
    lines = [l for l in r.stdout.splitlines() if (":109" in l or ":447" in l or ":22" in l) and "ESTAB" in l]
    return f"\U0001F50C Active SSH/WS sessions (approx): {len(lines)}"

def status_text():
    def st(svc):
        r = sh(["systemctl", "is-active", svc])
        return "\U0001F7E2 ACTIVE" if r.stdout.strip() == "active" else "\U0001F534 INACTIVE"

    dom = get_domain()
    return (
        f"\U0001F30D Domain: {dom}\n\n"
        f"Nginx: {st('nginx')}\n"
        f"Dropbear: {st('dropbear')}\n"
        f"WS Proxy: {st('ws-proxy')}\n"
        f"Auto-Kill: {st('autokill')}"
    )

def set_domain(new_domain):
    os.makedirs("/etc/zainuxbrand", exist_ok=True)
    with open(DOMAIN_FILE, "w") as f:
        f.write(new_domain)
    apply_nginx_config()

def setup_ssl():
    dom = get_domain()
    if dom == "No Domain Set":
        return False, "Pehle domain set karein."
    sh(["systemctl", "stop", "nginx"])
    r = sh([
        "certbot", "certonly", "--standalone", "--preferred-challenges", "http",
        "--agree-tos", "--register-unsafely-without-email", "-d", dom,
    ])
    ok = os.path.exists(f"/etc/letsencrypt/live/{dom}/fullchain.pem")
    if ok:
        apply_nginx_config()
        return True, "SSL issued successfully."
    return False, "SSL fail ho gaya. Domain A record VPS IP par pointed hai check karein."

def fix_websocket():
    sh(["systemctl", "restart", "dropbear"])
    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "restart", "ws-proxy"])
    sh(["systemctl", "restart", "autokill"])
    apply_nginx_config()
    return "WebSocket & Bandwidth engine restarted."

WS_PROXY_SRC = """import socket, threading, select, time

PORT = 2082
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\\n")
    except Exception:
        pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        if not request:
            client_socket.close()
            return

        for line in request.split('\\r\\n'):
            if line.lower().startswith('x-forwarded-for:') or line.lower().startswith('x-real-ip:'):
                real_ip = line.split(':')[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)

        response = "HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\n\\r\\n"
        client_socket.sendall(response.encode('utf-8'))

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_socket, target_socket]
        client_socket.settimeout(None)

        while True:
            readable, _, _ = select.select(sockets, [], [])
            for s in readable:
                other = target_socket if s is client_socket else client_socket
                data = s.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
"""

WS_PROXY_SERVICE = """[Unit]
Description=zainuxbrand WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
"""

AUTOKILL_SRC = """import os
import subprocess
import re
import time

USER_DIR = "/etc/zainuxbrand/users"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception:
        pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\\n" + f.read()
        except Exception:
            pass
    return raw

def get_active_users_and_pids(raw_logs):
    user_pids = {}
    try:
        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        for line in ps_out.splitlines():
            if "dropbear" in line and "grep" not in line:
                parts = line.split()
                if len(parts) > 1:
                    pid = parts[1]
                    matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
                    if matches:
                        last_line = matches[-1]
                        m = re.search(r"for \\x27(\\w+)\\x27", last_line)
                        if not m:
                            m = re.search(r"for (\\w+)", last_line)
                        if m:
                            uname = m.group(1)
                            if uname not in user_pids:
                                user_pids[uname] = []
                            user_pids[uname].append(pid)
    except Exception:
        pass
    return user_pids

def get_pid_io_bytes(pid):
    io_file = f"/proc/{pid}/io"
    total_bytes = 0
    if os.path.exists(io_file):
        try:
            with open(io_file, "r") as f:
                for line in f:
                    if line.startswith("rchar:") or line.startswith("wchar:"):
                        total_bytes += int(line.split(":")[1].strip())
        except Exception:
            pass
    return total_bytes

last_pid_bytes = {}

while True:
    try:
        raw_logs = get_auth_logs()
        user_pids_map = get_active_users_and_pids(raw_logs)

        if os.path.exists(USER_DIR):
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue

                uname = fname[:-5]
                conf_path = os.path.join(USER_DIR, fname)

                ip_limit = 0
                gb_limit = "Unlimited"
                used_mb = 0.0

                with open(conf_path, "r") as f:
                    lines = f.readlines()

                for line in lines:
                    if line.startswith("IP_LIMIT="):
                        try: ip_limit = int(line.strip().split("=")[1])
                        except Exception: pass
                    elif line.startswith("GB_LIMIT="):
                        gb_limit = line.strip().split("=")[1]
                    elif line.startswith("USED_MB="):
                        try: used_mb = float(line.strip().split("=")[1])
                        except Exception: pass

                active_pids = user_pids_map.get(uname, [])

                for pid in active_pids:
                    current_b = get_pid_io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = current_b - last_pid_bytes[pid]
                        if diff > 0:
                            used_mb += (diff / (1024.0 * 1024.0))
                    last_pid_bytes[pid] = current_b

                new_lines = []
                for line in lines:
                    if line.startswith("USED_MB="):
                        new_lines.append(f"USED_MB={used_mb:.2f}\\n")
                    else:
                        new_lines.append(line)
                with open(conf_path, "w") as f:
                    f.writelines(new_lines)

                if gb_limit != "Unlimited":
                    try:
                        max_mb = float(gb_limit) * 1024.0
                        if used_mb >= max_mb:
                            subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            for pid in active_pids:
                                subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass

                if ip_limit > 0 and len(active_pids) > ip_limit:
                    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for pid in active_pids:
                        subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    except Exception:
        pass

    time.sleep(3)
"""

AUTOKILL_SERVICE = """[Unit]
Description=zainuxbrand Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
"""

DEFAULT_BANNER = (
    '<font color="green">==========================================</font><br>\n'
    '<font color="yellow"><b>WELCOME TO zainuxbrand VIP VPN</b></font><br>\n'
    '<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>\n'
    '<font color="green">==========================================</font><br>\n'
)

def install_components_sync():
    sh(["apt-get", "update", "-y"])
    sh([
        "apt-get", "install", "-y", "curl", "wget", "unzip", "tar", "net-tools",
        "socat", "jq", "openssl", "nginx", "dropbear", "certbot", "python3",
        "python3-pip", "lsof", "iptables",
    ])

    if not os.path.exists(BANNER_FILE) or os.path.getsize(BANNER_FILE) == 0:
        with open(BANNER_FILE, "w") as f:
            f.write(DEFAULT_BANNER)

    run("bash -c '$(declare -f fix_dropbear_core); fix_dropbear_core'")

    run("sed -i 's/#Banner none/Banner \\/etc\\/issue.net/g' /etc/ssh/sshd_config")
    sh(["systemctl", "restart", "ssh"])

    with open("/usr/local/bin/ws-proxy.py", "w") as f:
        f.write(WS_PROXY_SRC)
    sh(["chmod", "+x", "/usr/local/bin/ws-proxy.py"])
    with open("/etc/systemd/system/ws-proxy.service", "w") as f:
        f.write(WS_PROXY_SERVICE)

    with open("/usr/local/bin/autokill.py", "w") as f:
        f.write(AUTOKILL_SRC)
    sh(["chmod", "+x", "/usr/local/bin/autokill.py"])
    with open("/etc/systemd/system/autokill.service", "w") as f:
        f.write(AUTOKILL_SERVICE)

    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "enable", "ws-proxy"])
    sh(["systemctl", "restart", "ws-proxy"])
    sh(["systemctl", "enable", "autokill"])
    sh(["systemctl", "restart", "autokill"])

    apply_nginx_config()

def uninstall_all():
    sh(["systemctl", "stop", "ws-proxy"])
    sh(["systemctl", "stop", "autokill"])
    sh(["systemctl", "stop", "dropbear"])
    sh(["systemctl", "disable", "ws-proxy"])
    sh(["systemctl", "disable", "autokill"])
    for f in [
        "/etc/systemd/system/ws-proxy.service",
        "/etc/systemd/system/autokill.service",
        "/etc/systemd/system/dropbear.service.d/override.conf",
        "/usr/local/bin/ws-proxy.py",
        "/usr/local/bin/autokill.py",
        "/etc/nginx/conf.d/vpn.conf",
    ]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass
    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "restart", "nginx"])
    if os.path.isdir(USERS_DIR):
        for fname in os.listdir(USERS_DIR):
            if fname.endswith(".conf"):
                sh(["userdel", "-f", fname[:-5]])
    sh(["rm", "-rf", "/etc/zainuxbrand"])
    sh(["rm", "-rf", "/opt/rr-tgbot-venv"])
    for f in ["/usr/local/bin/menu", "/usr/bin/menu"]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass

def schedule_self_removal():
    subprocess.Popen([
        "bash", "-c",
        "sleep 3 && systemctl disable tgbot 2>/dev/null; "
        "systemctl stop tgbot 2>/dev/null; "
        "rm -f /etc/systemd/system/tgbot.service /usr/local/bin/tgbot.py; "
        "systemctl daemon-reload",
    ])

def back_keyboard():
    return InlineKeyboardMarkup([[InlineKeyboardButton("\u2B05\uFE0F Back to Menu", callback_data="back_main")]])

def main_menu_keyboard(uid):
    rows = [
        [InlineKeyboardButton("\u2795 Add User", callback_data="add_user"),
         InlineKeyboardButton("\U0001F5D1 Delete User", callback_data="del_user")],
        [InlineKeyboardButton("\U0001F4CB User List", callback_data="list_users"),
         InlineKeyboardButton("\u23F3 Renew User", callback_data="renew_user")],
        [InlineKeyboardButton("\U0001F310 IP Limit", callback_data="ip_limit"),
         InlineKeyboardButton("\U0001F4BE GB Limit", callback_data="gb_limit")],
        [InlineKeyboardButton("\U0001F50C Connected IPs", callback_data="conn_ips"),
         InlineKeyboardButton("\u2699\uFE0F Status", callback_data="sys_status")],
        [InlineKeyboardButton("\U0001F30D Domain", callback_data="domain"),
         InlineKeyboardButton("\U0001F512 SSL", callback_data="ssl")],
        [InlineKeyboardButton("\U0001F4E2 Banner", callback_data="banner"),
         InlineKeyboardButton("\U0001F6E0 Fix WebSocket", callback_data="fix_ws")],
        [InlineKeyboardButton("\U0001F4E6 Install Components", callback_data="install"),
         InlineKeyboardButton("\U0001F9E8 Uninstall Panel", callback_data="uninstall")],
    ]
    if is_super(uid):
        rows.append([InlineKeyboardButton("\U0001F451 Admin Management", callback_data="admin_mgmt")])
    return InlineKeyboardMarkup(rows)

def admins_text():
    cfg = load_config()
    admins = load_admins()
    lines = ["\U0001F451 *Admin Management*\n"]
    for a in admins:
        tag = " (Super Admin)" if a == cfg.get("super_admin") else ""
        lines.append(f"\u2022 `{a}`{tag}")
    return "\n".join(lines)

def admin_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("\u2795 Add Admin", callback_data="add_admin"),
         InlineKeyboardButton("\u2796 Remove Admin", callback_data="remove_admin")],
        [InlineKeyboardButton("\u2B05\uFE0F Back", callback_data="back_main")],
    ])

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        await update.message.reply_text("\u26D4 Access Denied. Aap authorized admin nahi hain.")
        return
    context.user_data['flow'] = None
    await update.message.reply_text(
        f"\U0001F44B Welcome to {PANEL_NAME}\n\nApna option chunein:",
        reply_markup=main_menu_keyboard(uid),
    )

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['flow'] = None
    await update.message.reply_text("Cancelled.")

async def execute_flow(flow, data, update: Update):
    if flow == "add_user":
        ok, info = add_user(data["username"], data["password"], data["days"], data["ip_limit"], data["gb_limit"])
        if ok:
            dom = get_domain()
            payload = f"GET /zainuxbrand HTTP/1.1[crlf]Host: {dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
            msg = (
                f"\u2705 *Account Created*\n\n"
                f"Domain: `{dom}`\n"
                f"Username: `{data['username']}`\n"
                f"Password: `{data['password']}`\n"
                f"Expiry: `{info}`\n"
                f"IP Limit: `{data['ip_limit']}`\n"
                f"GB Limit: `{data['gb_limit']}`\n\n"
                f"SSH Direct: 22, 109, 447\nSSH WS (HTTP): 80\nSSH WS (SSL): 443\n\n"
                f"Payload:\n`{payload}`"
            )
        else:
            msg = f"\u274C User create fail: {info}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=back_keyboard())
    elif flow == "renew_user":
        ok = renew_user(data["username"], data["days"])
        await update.message.reply_text(
            "\u2705 Renewed." if ok else "\u274C User not found.", reply_markup=back_keyboard()
        )
    elif flow == "ip_limit":
        ok = update_conf_field(data["username"], "IP_LIMIT", data["value"])
        await update.message.reply_text(
            "\u2705 IP limit updated." if ok else "\u274C User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "gb_limit":
        ok = update_conf_field(data["username"], "GB_LIMIT", data["value"])
        await update.message.reply_text(
            "\u2705 GB limit updated." if ok else "\u274C User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "domain":
        set_domain(data["value"])
        await update.message.reply_text(f"\u2705 Domain set to {data['value']}", reply_markup=back_keyboard())
    elif flow == "banner":
        with open(BANNER_FILE, "w") as f:
            f.write(data["value"])
        sh(["systemctl", "restart", "dropbear"])
        sh(["systemctl", "restart", "ssh"])
        await update.message.reply_text("\u2705 Banner updated.", reply_markup=back_keyboard())
    elif flow == "add_admin":
        try:
            new_id = int(data["value"])
        except ValueError:
            await update.message.reply_text("\u274C Invalid ID.")
            return
        admins = load_admins()
        if new_id in admins:
            await update.message.reply_text("\u26A0\uFE0F Already an admin.")
        else:
            admins.append(new_id)
            save_admins(admins)
            await update.message.reply_text(f"\u2705 Admin {new_id} added.", reply_markup=admin_menu_keyboard())

async def text_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        return
    flow = context.user_data.get('flow')
    if not flow:
        return
    step = context.user_data.get('step', 0)
    field, _ = FLOWS[flow][step]
    context.user_data.setdefault('data', {})[field] = update.message.text.strip()
    step += 1
    if step < len(FLOWS[flow]):
        context.user_data['step'] = step
        await update.message.reply_text(FLOWS[flow][step][1])
        return

    data = context.user_data['data']
    context.user_data['flow'] = None

    if flow == "del_user":
        username = data["username"]
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Confirm Delete", callback_data=f"do_del:{username}"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"\u26A0\uFE0F '{username}' delete karna confirm karein:", reply_markup=kb)
        return

    if flow == "remove_admin":
        try:
            target = int(data["value"])
        except ValueError:
            await update.message.reply_text("\u274C Invalid ID.")
            return
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await update.message.reply_text("\u274C Super admin remove nahi ho sakta.")
            return
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Confirm Remove", callback_data=f"rm_admin:{target}"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"\u26A0\uFE0F Admin {target} remove karna confirm karein:", reply_markup=kb)
        return

    await execute_flow(flow, data, update)

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    uid = q.from_user.id
    if not is_admin(uid):
        await q.answer("Access denied.", show_alert=True)
        return
    data = q.data
    await q.answer()

    if data == "back_main":
        context.user_data['flow'] = None
        await q.edit_message_text("\U0001F4CB Main Menu", reply_markup=main_menu_keyboard(uid))
    elif data in FLOWS:
        context.user_data['flow'] = data
        context.user_data['step'] = 0
        context.user_data['data'] = {}
        field, prompt = FLOWS[data][0]
        await q.edit_message_text(prompt)
    elif data == "list_users":
        await q.edit_message_text(list_users_text(), reply_markup=back_keyboard())
    elif data == "conn_ips":
        await q.edit_message_text(connected_ips_text(), reply_markup=back_keyboard())
    elif data == "sys_status":
        await q.edit_message_text(status_text(), reply_markup=back_keyboard())
    elif data == "ssl":
        await q.edit_message_text("\U0001F512 SSL issue ho raha hai, wait karein...")
        ok, msg = await asyncio.to_thread(setup_ssl)
        await q.message.reply_text(("\u2705 " if ok else "\u274C ") + msg, reply_markup=back_keyboard())
    elif data == "fix_ws":
        msg = fix_websocket()
        await q.edit_message_text(f"\u2705 {msg}", reply_markup=back_keyboard())
    elif data == "install":
        await q.edit_message_text("\U0001F4E6 Poora system install ho raha hai (packages + Dropbear + WebSocket + Auto-Kill), 2-5 min lagega...")
        await asyncio.to_thread(install_components_sync)
        await q.message.reply_text(
            "\u2705 Installation complete! Packages, Dropbear, Banner, WebSocket Proxy aur "
            "Auto-Kill/Bandwidth service sab deploy ho gaye hain.\n"
            "\u2139\uFE0F Agar aapne pehle domain set nahi kiya to Nginx SSL block abhi apply nahi hoga "
            "\u2014 pehle Domain option se domain set karein, phir SSL issue karein.",
            reply_markup=back_keyboard(),
        )
    elif data == "uninstall":
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Haan, Uninstall karein", callback_data="do_uninstall"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await q.edit_message_text(
            "\u26A0\uFE0F Yeh sab kuch permanently remove kar dega (users, services, config, is bot samet). "
            "Confirm karein:",
            reply_markup=kb,
        )
    elif data == "do_uninstall":
        await q.edit_message_text("\U0001F9E8 Uninstalling...")
        await asyncio.to_thread(uninstall_all)
        await q.message.reply_text("\u2705 Uninstall complete. Bot khud bhi band ho raha hai.")
        schedule_self_removal()
    elif data == "admin_mgmt":
        if not is_super(uid):
            await q.answer("Sirf Super Admin ke liye.", show_alert=True)
            return
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())
    elif data.startswith("do_del:"):
        username = data.split(":", 1)[1]
        delete_user(username)
        await q.edit_message_text(f"\u2705 User {username} deleted.", reply_markup=back_keyboard())
    elif data.startswith("rm_admin:"):
        target = int(data.split(":", 1)[1])
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await q.answer("Super admin remove nahi ho sakta.", show_alert=True)
            return
        admins = load_admins()
        if target in admins:
            admins.remove(target)
            save_admins(admins)
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())

def main():
    cfg = load_config()
    app = Application.builder().token(cfg["token"]).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("cancel", cancel))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__":
    main()
PY_EOF
    chmod +x /usr/local/bin/tgbot.py

    cat << 'SVC_EOF' > /etc/systemd/system/tgbot.service
[Unit]
Description=zainuxbrand Telegram Bot
After=network.target

[Service]
ExecStart=/opt/rr-tgbot-venv/bin/python3 /usr/local/bin/tgbot.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF
}

apply_nginx_config() {
    local MY_DOMAIN=$(get_domain)

    if [[ "$MY_DOMAIN" == "No Domain Set" || -z "$MY_DOMAIN" ]]; then
        return 1
    fi

    # Ensure nginx is installed and config directory exists
    if ! dpkg -l nginx 2>/dev/null | grep -q "^ii"; then
        echo -e "${YELLOW}[INSTALL] Nginx missing hai. Install kar rahe hain...${NC}"
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y nginx >/dev/null 2>&1 || {
            echo -e "${RED}[ERROR] Nginx install nahi ho saka!${NC}"
            return 1
        }
    fi
    mkdir -p /etc/nginx/conf.d
    local cert_file="/root/cert/${MY_DOMAIN}/fullchain.pem"
    local key_file="/root/cert/${MY_DOMAIN}/privkey.pem"
    local has_ssl=0
    [[ -f "$cert_file" && -f "$key_file" ]] && has_ssl=1

    cat << NGX_EOF > /etc/nginx/conf.d/vpn.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${MY_DOMAIN} _;

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${CUSTOM_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGX_EOF

    # Only add 443 SSL server if cert exists (nginx won't start with missing cert)
    if [[ "$has_ssl" == "1" ]]; then
        cat << NGX_SSL >> /etc/nginx/conf.d/vpn.conf

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name ${MY_DOMAIN} _;

    ssl_certificate ${cert_file};
    ssl_certificate_key ${key_file};
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${CUSTOM_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGX_SSL
    fi

    rm -f /etc/nginx/sites-enabled/default
    nginx -t >/dev/null 2>&1 && systemctl restart nginx 2>/dev/null || {
        echo -e "${YELLOW}[WARNING] Nginx config test fail hua. Default config regenerate kar rahe hain...${NC}"
        rm -f /etc/nginx/conf.d/vpn.conf
        systemctl restart nginx 2>/dev/null || true
    }
}

add_domain_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}        ADD / CHANGE DOMAIN NAME                    ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    read -rp " Apna Domain Enter Karein (e.g. sub.yourdomain.com): " new_dom

    if [[ -z "$new_dom" ]]; then
        echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte!${NC}"
    elif [[ "$new_dom" != *.* ]]; then
        echo -e "${RED}[ERROR] '${new_dom}' valid domain nahi hai (dot chahiye).${NC}"
    else
        mkdir -p /etc/zainuxbrand
        echo "$new_dom" > "$DOMAIN_FILE"
        echo -e "\n${GREEN}[SUCCESS] Domain set: ${CYAN}${new_dom}${NC}"

        # Auto-update everything for new domain
        echo -e "${BLUE}[1/3] Nginx config update...${NC}"
        apply_nginx_config

        echo -e "${BLUE}[2/3] SSL certificate issue for ${new_dom}...${NC}"
        issue_ssl_acme "$new_dom"

        echo -e "${BLUE}[3/3] 3X-UI config update...${NC}"
        mkdir -p /etc/zainuxbrand
        cat > /etc/zainuxbrand/xui.conf << XUICONF
PANEL_USER="admin"
PANEL_PASS="zaini123"
PANEL_PORT="8443"
PANEL_DOMAIN="$new_dom"
CERT_PATH="/root/cert/${new_dom}/fullchain.pem"
KEY_PATH="/root/cert/${new_dom}/privkey.pem"
XUICONF
        chmod 600 /etc/zainuxbrand/xui.conf 2>/dev/null
        systemctl restart x-ui 2>/dev/null

        echo -e "\n${GREEN}[SUCCESS] Domain change complete!${NC}"
        echo -e "${CYAN}Domain     : $new_dom${NC}"
        echo -e "${CYAN}Cert Path  : /root/cert/${new_dom}/fullchain.pem${NC}"
    fi
    press_any_key
}

install_all_components() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION           ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${BLUE}[PRE-CHECK] Internet aur DNS check...${NC}"
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Internet connection nahi hai!${NC}"
        echo -e "${YELLOW}Fix karein: echo 'nameserver 8.8.8.8' > /etc/resolv.conf${NC}"
        press_any_key
        return
    fi
    if ! getent hosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARNING] DNS slow/fail ho raha hai. Google DNS set kar rahe hain...${NC}"
        rm -f /etc/resolv.conf
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
    if ! curl -s4 --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARNING] IPv4 GitHub access fail. IPv6 disable kar rahe hain...${NC}"
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Internet aur DNS theek hain.${NC}\n"

    echo -e "${BLUE}[1/6] Updating Packages...${NC}"
    apt-get update -y && apt-get upgrade -y

    echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"
    ensure_base_packages || {
        echo -e "${RED}[ERROR] Base packages install nahi ho sake. Install cancel.${NC}"
        press_any_key
        return
    }

    echo -e "${BLUE}[3/6] Configuring Dropbear SSH & Banner...${NC}"

    cat << 'BANNER_EOF' > $BANNER_FILE
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO ZAINUXBRAND VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
BANNER_EOF

    fix_dropbear_core

    sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
    systemctl restart ssh

    echo -e "${BLUE}[4/6] Creating Multi-Payload Python WebSocket Service...${NC}"
    cat << 'WS_EOF' > /usr/local/bin/ws-proxy.py
import socket, threading, select, time

PORT = 2082
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    except Exception:
        pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        if not request:
            client_socket.close()
            return

        for line in request.split('\r\n'):
            if line.lower().startswith('x-forwarded-for:') or line.lower().startswith('x-real-ip:'):
                real_ip = line.split(':')[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)

        response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        client_socket.sendall(response.encode('utf-8'))

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_socket, target_socket]
        client_socket.settimeout(None)

        while True:
            readable, _, _ = select.select(sockets, [], [])
            for s in readable:
                other = target_socket if s is client_socket else client_socket
                data = s.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
WS_EOF

    cat << SVC_EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=zainuxbrand WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable ws-proxy
    systemctl restart ws-proxy
    apply_nginx_config

    echo -e "${BLUE}[5/6] Installing Bandwidth & IPTables Tracking Engine...${NC}"
    install_python_tracker

    echo -e "\n${GREEN}[SUCCESS] Base components & Protection Engine Installed!${NC}"
    press_any_key
}

setup_ssl() {
    clear
    local current_dom=$(get_domain)

    if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Option 2 se Domain Add karein!${NC}"
        press_any_key
        return
    fi

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}  ${PANEL_NAME} - ISSUING SSL (${current_dom}) ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    if issue_ssl_acme "$current_dom"; then
        apply_nginx_config
        echo -e "${GREEN}[SUCCESS] Nginx SSL & WebSocket Proxy Configured!${NC}"
    fi

    press_any_key
}

check_connected_ips() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     CONNECTED IPS & ACTIVE USERS                   ${NC}"
    echo -e "${CYAN}====================================================================${NC}"

    echo -e "${GREEN}Active Online SSH / WebSocket Sessions:${NC}"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    local total_count=0
    local raw_logs=""
    if command -v journalctl &>/dev/null; then
        raw_logs=$(journalctl -u dropbear --no-pager -n 400 2>/dev/null)
    fi
    [[ -f "/var/log/auth.log" ]] && raw_logs+=$'\n'$(cat /var/log/auth.log 2>/dev/null)

    mapfile -t external_ips < <(ss -tnp 2>/dev/null | grep -E ":(80|443|2082)" | grep "ESTAB" | awk '{print $5}' | cut -d: -f1 | grep -vE "^127\.|^::1" | sort -u)
    mapfile -t ws_logged_ips < <(grep -oP "(?<=REAL_IP:)\S+" /var/log/ws-proxy.log 2>/dev/null | tail -n 20 | sort -u)

    local real_ip_pool=($(echo "${external_ips[@]} ${ws_logged_ips[@]}" | tr ' ' '\n' | sort -u))
    local ip_index=0

    for pid in $(ps aux | grep dropbear | grep -v grep | awk '{print $2}'); do
        local user_match=$(echo "$raw_logs" | grep "dropbear\[$pid\]" | grep -i "Password auth succeeded" | tail -n 1)

        if [[ -n "$user_match" ]]; then
            local username=$(echo "$user_match" | grep -oP "(?<=for ')\w+(?=')" || echo "$user_match" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
            local logged_ip=$(echo "$user_match" | grep -oP "(?<=from )\S+(?=:)")
            local final_ip="$logged_ip"

            if [[ "$logged_ip" == "127.0.0.1" || -z "$logged_ip" ]]; then
                if [[ ${#real_ip_pool[@]} -gt 0 && $ip_index -lt ${#real_ip_pool[@]} ]]; then
                    final_ip="${real_ip_pool[$ip_index]} (WS Tunnel)"
                    ip_index=$((ip_index + 1))
                else
                    final_ip="WS-Proxy Client"
                fi
            fi

            if [[ -n "$username" ]]; then
                printf " User: %-18s | IP/Source: %-25s [ONLINE]\n" "$username" "$final_ip"
                total_count=$((total_count + 1))
            fi
        fi
    done

    local active_sockets=$(ss -tnp 2>/dev/null | grep -E ":(109|447|22)" | grep -i "ESTAB" | wc -l)
    if [[ $total_count -lt $active_sockets ]]; then
        echo -e "${YELLOW} Detected ${active_sockets} Active Tunnel Socket(s) connected to Dropbear Core.${NC}"
        [[ $total_count -eq 0 ]] && total_count=$active_sockets
    fi

    if [[ $total_count -eq 0 ]]; then
        echo -e "${YELLOW} Filhal koi active user connected nahi hai.${NC}"
    fi

    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Total Active Sessions: ${BOLD}${total_count}${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

check_gb_usage() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                USER BANDWIDTH / EXPIRY & LOCK STATUS               ${NC}"
    echo -e "${CYAN}====================================================================${NC}"

    printf " %-14s | %-7s | %-10s | %-12s | %-10s\n" "USERNAME" "IP LIMIT" "DATA USED" "DATA LIMIT" "STATUS"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    mkdir -p /etc/zainuxbrand/users

    for conf in /etc/zainuxbrand/users/*.conf; do
        [[ -e "$conf" ]] || continue
        local uname=$(basename "$conf" .conf)
        local limit=$(grep "^GB_LIMIT=" "$conf" | cut -d= -f2)
        local ip_l=$(grep "^IP_LIMIT=" "$conf" | cut -d= -f2)
        local used_mb=$(grep "^USED_MB=" "$conf" | cut -d= -f2)

        [[ -z "$limit" ]] && limit="Unlimited"
        [[ -z "$ip_l" ]] && ip_l="1"
        [[ -z "$used_mb" ]] && used_mb="0"

        local used_gb=$(python3 -c "print(f'{$used_mb/1024:.2f}')")

        local status="${GREEN}Active${NC}"
        if id "$uname" &>/dev/null; then
            if passwd -S "$uname" 2>/dev/null | grep -q "L"; then
                status="${RED}LOCKED${NC}"
            fi
        else
            status="${RED}Deleted${NC}"
        fi

        printf " %-14s | %-8s | %-7s GB | %-9s GB | %b\n" "$uname" "$ip_l" "$used_gb" "$limit" "$status"
    done

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

user_menu() {
    local cur_dom=$(get_domain)
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}       ${PANEL_NAME} - USER MANAGEMENT           ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Add New User"
        echo -e " 2) Delete User"
        echo -e " 3) Check Connected IPs & Active Online Users"
        echo -e " 4) Check User Status, Quota & Limits"
        echo -e " 5) Renew Account Expiry Days"
        echo -e " 6) Extend / Modify IP Limit (Auto Unlock)"
        echo -e " 7) Extend / Modify GB Data Quota (Auto Unlock)"
        echo -e " 8) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-8]: " u_choice

        case $u_choice in
            1)
                read -rp "Username: " username
                read -rp "Password: " password
                read -rp "Days Expiry (e.g. 30): " days
                read -rp "Max IP Limit (e.g. 1 ya 2): " ip_limit
                read -rp "Quota / Data Limit in GB (e.g. 0.5 ya 50): " gb_limit

                exp_date=$(date -d "+$days days" +%Y-%m-%d)

                useradd -M -s /bin/bash -e "$exp_date" "$username"
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}[ERROR] User create nahi hua! Upar wala error dekhein (username already exists ho sakta hai).${NC}"
                    press_any_key
                    continue
                fi
                echo "$username:$password" | chpasswd
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}[ERROR] Password set nahi hua!${NC}"
                fi

                mkdir -p /etc/zainuxbrand/users
                echo "IP_LIMIT=$ip_limit" > "/etc/zainuxbrand/users/${username}.conf"
                echo "GB_LIMIT=$gb_limit" >> "/etc/zainuxbrand/users/${username}.conf"
                echo "USED_MB=0.0" >> "/etc/zainuxbrand/users/${username}.conf"

                echo -e "\n${GREEN}====================================================${NC}"
                echo -e "${YELLOW}           ACCOUNT CREATED BY ZAINUXBRAND          ${NC}"
                echo -e "${GREEN}====================================================${NC}"
                echo -e " Domain       : ${CYAN}${cur_dom}${NC}"
                echo -e " Username     : ${CYAN}${username}${NC}"
                echo -e " Password     : ${CYAN}${password}${NC}"
                echo -e " Expired On   : ${CYAN}${exp_date}${NC}"
                echo -e " Max IP Limit : ${CYAN}${ip_limit} Device(s)${NC}"
                echo -e " Data Limit   : ${CYAN}${gb_limit} GB${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                echo -e " SSH Direct   : ${CYAN}22, 109, 447${NC}"
                echo -e " SSH WS (HTTP): ${CYAN}80${NC}"
                echo -e " SSH WS (SSL) : ${CYAN}443${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                echo -e " Payload      :"
                echo -e "${CYAN}GET ${CUSTOM_PATH} HTTP/1.1[crlf]Host: ${cur_dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                press_any_key
                ;;
            2)
                echo -e "${CYAN}--- Existing Users ---${NC}"
                mkdir -p /etc/zainuxbrand/users
                local found=0
                for conf in /etc/zainuxbrand/users/*.conf; do
                    [[ -e "$conf" ]] || continue
                    local uname=$(basename "$conf" .conf)
                    local exp=$(chage -l "$uname" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
                    [[ -z "$exp" ]] && exp="N/A"
                    printf "  - %-18s (expires: %s)\n" "$uname" "$exp"
                    found=1
                done
                [[ $found -eq 0 ]] && echo -e "${YELLOW}  Koi user nahi mila.${NC}"
                echo -e "${CYAN}----------------------${NC}"
                read -rp "Username to delete: " username
                if [[ -z "$username" ]]; then
                    echo -e "${RED}[ERROR] Username khaali nahi chhod sakte!${NC}"
                    press_any_key
                    continue
                fi
                userdel -f "$username" 2>/dev/null
                rm -f "/etc/zainuxbrand/users/${username}.conf"
                echo -e "${GREEN}User ${username} deleted successfully!${NC}"
                press_any_key
                ;;
            3) check_connected_ips ;;
            4) check_gb_usage ;;
            5)
                read -rp "Username to Renew: " username
                if id "$username" &>/dev/null; then
                    read -rp "Kitne additional days add karne hain? (e.g. 30): " r_days
                    new_exp=$(date -d "+$r_days days" +%Y-%m-%d)
                    usermod -e "$new_exp" "$username"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] User ${username} Expiry Extended. New Expiry: ${new_exp}${NC}"
                else
                    echo -e "${RED}[ERROR] User exist nahi karta!${NC}"
                fi
                press_any_key
                ;;
            6)
                read -rp "Username to change IP Limit: " username
                if [[ -f "/etc/zainuxbrand/users/${username}.conf" ]]; then
                    read -rp "Nayi IP Limit enter karein (e.g. 2 ya 3): " new_ip_l
                    sed -i "s/IP_LIMIT=.*/IP_LIMIT=${new_ip_l}/g" "/etc/zainuxbrand/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] IP limit updated to ${new_ip_l} Device(s).${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                fi
                press_any_key
                ;;
            7)
                read -rp "Username to extend GB limit: " username
                if [[ -f "/etc/zainuxbrand/users/${username}.conf" ]]; then
                    read -rp "Naya Data Limit GB me enter karein (e.g. 1 ya 50): " new_gb
                    sed -i "s/GB_LIMIT=.*/GB_LIMIT=${new_gb}/g" "/etc/zainuxbrand/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] GB Limit updated to ${new_gb} GB.${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                fi
                press_any_key
                ;;
            8) return ;;
            *) echo "Invalid Option"; sleep 1 ;;
        esac
    done
}

status_check() {
    clear
    local current_dom=$(get_domain)
    local nginx_status=$(systemctl is-active nginx 2>/dev/null)
    local dropbear_status=$(systemctl is-active dropbear 2>/dev/null)
    local ws_status=$(systemctl is-active ws-proxy 2>/dev/null)
    local ak_status=$(systemctl is-active autokill 2>/dev/null)

    local ngx_badge="${RED}[ INACTIVE ]${NC}"
    local db_badge="${RED}[ INACTIVE ]${NC}"
    local ws_badge="${RED}[ INACTIVE ]${NC}"
    local ak_badge="${RED}[ INACTIVE ]${NC}"

    [[ "$nginx_status" == "active" ]] && ngx_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$dropbear_status" == "active" ]] && db_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ws_status" == "active" ]] && ws_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ak_status" == "active" ]] && ak_badge="${GREEN}[ ACTIVE ]${NC}"

    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Target Domain : ${BOLD}${current_dom}${NC}"
    echo -e " Active Path   : ${BOLD}${CUSTOM_PATH}${NC}\n"

    echo -e "${CYAN} SERVICES STATUS${NC}"
    echo -e "${CYAN} ------------------------------------------------------------------${NC}"
    printf "   %-28s : %b\n" "Nginx SSL Proxy Engine" "$ngx_badge"
    printf "   %-28s : %b\n" "Dropbear SSH Core" "$db_badge"
    printf "   %-28s : %b\n" "Python WebSocket Service" "$ws_badge"
    printf "   %-28s : %b\n" "Auto-Lock & Bandwidth Daemon" "$ak_badge"
    echo ""

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

set_banner() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - SET SSH / WS BANNER       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "1) Write HTML / Custom Banner"
    echo -e "2) View Current Banner"
    echo -e "3) Reset/Clear Banner"
    echo -e "4) Back"
    read -rp "Option [1-4]: " b_opt

    case $b_opt in
        1)
            echo -e "${YELLOW}Text banner paste karke [ENTER] dabayein (Ending line par END likhein):${NC}"
            > $BANNER_FILE
            while IFS= read -r line; do
                [[ $line == "END" ]] && break
                echo "$line" >> $BANNER_FILE
            done
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}[SUCCESS] Banner updated!${NC}"
            press_any_key
            ;;
        2)
            clear
            echo -e "${CYAN}--- Current SSH Banner ---${NC}"
            cat $BANNER_FILE
            press_any_key
            ;;
        3)
            echo "" > $BANNER_FILE
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}Banner cleared!${NC}"
            press_any_key
            ;;
        *) return ;;
    esac
}

fix_websocket() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       FIXING SSH WS & WS+SSL ENGINE               ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    ensure_base_packages || true
    fuser -k 109/tcp 2>/dev/null || true
    fix_dropbear_core
    # Only restart ws-proxy if service file exists
    if [[ -f /etc/systemd/system/ws-proxy.service ]]; then
        systemctl restart ws-proxy 2>/dev/null || true
    else
        echo -e "${YELLOW}[SKIP] ws-proxy service abhi install nahi hua.${NC}"
    fi
    install_python_tracker
    apply_nginx_config

    echo -e "\n${GREEN}[COMPLETED] WebSocket System & Bandwidth Engine Active!${NC}"
    press_any_key
}

setup_telegram_bot() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - TELEGRAM BOT SETUP          ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " 1) Install / Configure Bot (Token + Super Admin ID)"
    echo -e " 2) Restart Bot Service"
    echo -e " 3) Stop Bot Service"
    echo -e " 4) View Bot Status"
    echo -e " 5) Back"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Option [1-5]: " tb_opt

    case $tb_opt in
        1)
            echo -e "${YELLOW}Tip: Bot Token @BotFather se milta hai. Apna Telegram User ID @userinfobot se maloom karein.${NC}"
            read -rp "Telegram Bot Token enter karein: " bot_token
            read -rp "Apna Telegram User ID enter karein (yeh Super Admin banega): " super_id

            if [[ -z "$bot_token" || -z "$super_id" ]]; then
                echo -e "${RED}[ERROR] Token aur ID dono zaroori hain!${NC}"
                press_any_key
                return
            fi
            if ! [[ "$super_id" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}[ERROR] User ID sirf numbers ka hona chahiye!${NC}"
                press_any_key
                return
            fi

            echo -e "${BLUE}[1/5] Installing Python & venv...${NC}"
            apt install -y python3 python3-venv python3-pip

            echo -e "${BLUE}[2/5] Creating isolated virtual environment...${NC}"
            rm -rf /opt/rr-tgbot-venv
            python3 -m venv /opt/rr-tgbot-venv
            /opt/rr-tgbot-venv/bin/pip install --upgrade pip
            /opt/rr-tgbot-venv/bin/pip install "python-telegram-bot==20.7"

            if [[ $? -ne 0 ]]; then
                echo -e "${RED}[ERROR] Bot dependencies install nahi hui! Internet connection ya apt sources check karein.${NC}"
                press_any_key
                return
            fi

            echo -e "${BLUE}[3/5] Writing config...${NC}"
            mkdir -p /etc/zainuxbrand/tgbot
            cat << CFG_EOF > /etc/zainuxbrand/tgbot/config.json
{"token": "${bot_token}", "super_admin": ${super_id}}
CFG_EOF
            echo "[${super_id}]" > /etc/zainuxbrand/tgbot/admins.json

            echo -e "${BLUE}[4/5] Installing bot script...${NC}"
            install_tgbot_script

            echo -e "${BLUE}[5/5] Starting Telegram bot service...${NC}"
            systemctl daemon-reload
            systemctl enable tgbot
            systemctl restart tgbot

            echo -e "\n${GREEN}[SUCCESS] Telegram Bot Active! Apne bot ko Telegram par /start bhejein.${NC}"
            echo -e "${CYAN}Sirf aapki ID (${super_id}) ke paas Admin Management access hoga.${NC}"
            press_any_key
            ;;
        2)
            systemctl restart tgbot
            echo -e "${GREEN}Bot restarted.${NC}"
            press_any_key
            ;;
        3)
            systemctl stop tgbot
            echo -e "${YELLOW}Bot stopped.${NC}"
            press_any_key
            ;;
        4)
            clear
            systemctl status tgbot --no-pager
            press_any_key
            ;;
        *) return ;;
    esac
}

uninstall_panel() {
    clear
    echo -e "${RED}${BOLD}====================================================================${NC}"
    echo -e "${RED}${BOLD}          FULL UNINSTALL - VPS FRESH RESET                       ${NC}"
    echo -e "${RED}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}Yeh operation ye SAB kuch permanently remove kar dega:${NC}"
    echo -e "  ${RED}-3X-UI Panel + Xray Core (VLESS/VMess/Trojan)${NC}"
    echo -e "  ${RED}- SSH VPN System (Dropbear, WebSocket, Auto-Kill)${NC}"
    echo -e "  ${RED}- Telegram Bot service${NC}"
    echo -e "  ${RED}- Nginx VPN reverse-proxy config${NC}"
    echo -e "  ${RED}- SSL Certificates (acme.sh + Let's Encrypt + /root/cert)${NC}"
    echo -e "  ${RED}- Saare panel-created SSH users aur X-UI accounts${NC}"
    echo -e "  ${RED}- Domain config, banner, xui-helper, menu command${NC}"
    echo -e "  ${RED}- BBR sysctl entries${NC}"
    echo -e "${RED}Yeh action UNDO nahi ho sakta! VPS bilkul fresh ho jayega!${NC}\n"
    read -rp "Confirm karne ke liye 'YES' likhein (case-sensitive): " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo -e "${YELLOW}Uninstall cancel kar diya gaya.${NC}"
        press_any_key
        return
    fi

    echo -e "\n${BLUE}[1/10] Ensuring OpenSSH is installed BEFORE stopping Dropbear...${NC}"
    # CRITICAL: If Dropbear is on port 22, we MUST install & start OpenSSH first
    # otherwise VPS becomes inaccessible after Dropbear is removed!
    if ! dpkg -l | grep -q "openssh-server"; then
        echo -e "${YELLOW}openssh-server install ho raha hai (taake SSH access na khoye)...${NC}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y openssh-server >/dev/null 2>&1
    fi
    # Ensure sshd config allows root login on port 22
    if [[ -f /etc/ssh/sshd_config ]]; then
        sed -i 's/^#*Port .*/Port 22/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    # Generate host keys if missing
    ssh-keygen -A 2>/dev/null
    # Enable and start OpenSSH BEFORE touching Dropbear
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null
    systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null
    sleep 1
    # Verify OpenSSH is actually listening on port 22
    if ss -tlnp | grep -q ':22 '; then
        echo -e "${GREEN}[OK] OpenSSH (sshd) port 22 pe chal raha hai. Ab Dropbear safe stop ho sakta hai.${NC}"
    else
        echo -e "${YELLOW}[WARNING] OpenSSH port 22 pe nahi mila. Dropbear abhi stop nahi karenge!${NC}"
        echo -e "${YELLOW}SSH access bachane ke liye Dropbear ko chhodd rahe hain.${NC}"
        # Don't stop Dropbear if OpenSSH isn't ready!
        # Skip to stopping other services only
        systemctl stop x-ui 2>/dev/null
        systemctl stop ws-proxy 2>/dev/null
        systemctl stop autokill 2>/dev/null
        systemctl stop tgbot 2>/dev/null
        systemctl disable x-ui 2>/dev/null
        systemctl disable ws-proxy 2>/dev/null
        systemctl disable autokill 2>/dev/null
        systemctl disable tgbot 2>/dev/null
        # Jump past Dropbear stop/disable
        echo -e "${BLUE}Continuing uninstall (Dropbear left running for SSH access)...${NC}"
        # Skip the normal Dropbear stop/disable below
        SKIP_DROPBEAR=1
    fi

    if [[ "${SKIP_DROPBEAR:-0}" != "1" ]]; then
        systemctl stop x-ui 2>/dev/null
        systemctl stop ws-proxy 2>/dev/null
        systemctl stop autokill 2>/dev/null
        systemctl stop tgbot 2>/dev/null
        systemctl stop dropbear 2>/dev/null
        systemctl disable x-ui 2>/dev/null
        systemctl disable ws-proxy 2>/dev/null
        systemctl disable autokill 2>/dev/null
        systemctl disable tgbot 2>/dev/null
        systemctl disable dropbear 2>/dev/null
    fi

    echo -e "${BLUE}[2/10] Removing 3X-UI + Xray Core...${NC}"
    # 3x-ui official uninstall
    if [[ -f /usr/local/x-ui/install.sh ]]; then
        cd /usr/local/x-ui && ./install.sh uninstall 2>/dev/null
    fi
    rm -rf /usr/local/x-ui
    rm -f /usr/bin/x-ui /usr/local/bin/x-ui
    rm -rf /etc/x-ui
    rm -f /etc/systemd/system/x-ui.service
    rm -f /usr/local/x-ui/x-ui
    # Remove Xray binary
    rm -f /usr/local/x-ui/bin/xray-linux-amd64
    rm -f /usr/local/bin/xray /usr/bin/xray
    rm -rf /usr/local/etc/xray 2>/dev/null
    rm -rf /usr/share/xray 2>/dev/null

    echo -e "${BLUE}[3/10] Removing SSH VPN systemd services...${NC}"
    rm -f /etc/systemd/system/ws-proxy.service
    rm -f /etc/systemd/system/autokill.service
    rm -f /etc/systemd/system/tgbot.service
    rm -f /etc/systemd/system/dropbear.service.d/override.conf
    rm -rf /etc/systemd/system/dropbear.service.d
    systemctl daemon-reload

    echo -e "${BLUE}[4/10] Removing panel scripts & helpers...${NC}"
    rm -f /usr/local/bin/ws-proxy.py
    rm -f /usr/local/bin/autokill.py
    rm -f /usr/local/bin/tgbot.py
    rm -f /usr/local/bin/xui-helper.py
    rm -rf /opt/rr-tgbot-venv

    echo -e "${BLUE}[5/10] Removing SSL certificates (acme.sh + Let's Encrypt + /root/cert)...${NC}"
    # acme.sh
    /root/.acme.sh/acme.sh --uninstall 2>/dev/null
    rm -rf /root/.acme.sh
    # Let's Encrypt certs
    rm -rf /etc/letsencrypt
    # Panel cert directory
    rm -rf /root/cert

    echo -e "${BLUE}[6/10] Removing Nginx VPN config...${NC}"
    rm -f /etc/nginx/conf.d/vpn.conf
    rm -f /etc/nginx/conf.d/zainuxbrand*
    systemctl restart nginx 2>/dev/null

    echo -e "${BLUE}[7/10] Removing all panel-created SSH users...${NC}"
    if [[ -d /etc/zainuxbrand/users ]]; then
        for conf in /etc/zainuxbrand/users/*.conf; do
            [[ -e "$conf" ]] || continue
            local uname=$(basename "$conf" .conf)
            userdel -f "$uname" 2>/dev/null
        done
    fi

    echo -e "${BLUE}[8/10] Removing config files & banner...${NC}"
    rm -rf /etc/zainuxbrand
    # Reset SSH banner
    echo "" > /etc/issue.net 2>/dev/null
    sed -i 's/Banner \/etc\/issue.net/#Banner none/g' /etc/ssh/sshd_config 2>/dev/null
    systemctl restart ssh 2>/dev/null

    echo -e "${BLUE}[9/10] Removing BBR sysctl entries...${NC}"
    sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf 2>/dev/null
    sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf 2>/dev/null
    sysctl -p >/dev/null 2>&1

    echo -e "${BLUE}[10/10] Removing menu command & final cleanup...${NC}"
    rm -f /usr/local/bin/menu /usr/bin/menu

    # Purge packages that were installed by panel
    # CRITICAL: Don't purge dropbear unless OpenSSH is confirmed running on port 22
    echo -e "${YELLOW}Packages purge kar rahe hain (nginx, certbot)...${NC}"
    apt-get remove --purge -y nginx nginx-common certbot 2>/dev/null
    if ss -tlnp | grep -q ':22 '; then
        echo -e "${GREEN}[OK] OpenSSH port 22 pe confirmed. Dropbear purge ho raha hai...${NC}"
        apt-get remove --purge -y dropbear 2>/dev/null
    else
        echo -e "${YELLOW}[SKIP] Dropbear NOT purged — OpenSSH port 22 pe nahi mila!${NC}"
        echo -e "${YELLOW}SSH access ke liye Dropbear chhoda gaya.${NC}"
    fi
    apt-get autoremove -y 2>/dev/null

    # Reload systemd
    systemctl daemon-reload

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}       VPS FRESH RESET COMPLETE!                    ${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${YELLOW}Sab kuch delete ho gaya:${NC}"
    echo -e "  - 3X-UI + Xray Core        [GONE]"
    echo -e "  - SSH VPN System            [GONE]"
    echo -e "  - SSL Certificates          [GONE]"
    echo -e "  - All Users & Accounts      [GONE]"
    echo -e "  - Nginx, Certbot            [PURGED]"
    echo -e "  - BBR Settings              [RESET]"
    echo -e "  - Menu Command              [GONE]"
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}[IMPORTANT] SSH access SAFE hai — OpenSSH port 22 pe chal raha hai.${NC}"
    echo -e "${CYAN}VPS ab bilkul fresh hai!${NC}"
    echo -e "${CYAN}Phir se install karne ke liye script dobara run karein.${NC}"
    echo -e "${GREEN}====================================================${NC}"
    sleep 3
    exit 0
}

issue_ssl_acme() {
    local target_dom="$1"
    local silent="${2:-0}"
    local cert_path="/root/cert/${target_dom}/fullchain.pem"
    local key_path="/root/cert/${target_dom}/privkey.pem"

    [[ "$silent" != "1" ]] && echo -e "\n${BLUE}[SSL] Certificate issue kar rahe hain for ${target_dom}...${NC}"

    # Validate domain
    if [[ -z "$target_dom" || "$target_dom" == "No Domain Set" ]]; then
        echo -e "${RED}[ERROR] Domain set nahi hai!${NC}"
        return 1
    fi
    if [[ "$target_dom" != *.* ]]; then
        echo -e "${RED}[ERROR] '${target_dom}' valid domain nahi hai (dot chahiye).${NC}"
        return 1
    fi

    # DNS check
    local dns_ip=$(getent hosts "$target_dom" 2>/dev/null | awk '{print $1}' | head -1)
    local vps_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null)
    if [[ -n "$dns_ip" && -n "$vps_ip" && "$dns_ip" != "$vps_ip" ]]; then
        echo -e "${RED}[ERROR] DNS mismatch: ${target_dom} -> ${dns_ip}, VPS -> ${vps_ip}${NC}"
        echo -e "${YELLOW}Pehle domain A record ${vps_ip} par point karein.${NC}"
        return 1
    fi

    # Stop services using port 80
    systemctl stop nginx 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    sleep 1

    # Install acme.sh if missing
    if [[ ! -f /root/.acme.sh/acme.sh ]]; then
        [[ "$silent" != "1" ]] && echo -e "${YELLOW}acme.sh install ho raha hai...${NC}"
        if ! curl -4 -sL https://get.acme.sh | sh >/dev/null 2>&1; then
            echo -e "${RED}[ERROR] acme.sh install nahi hua!${NC}"
            systemctl start nginx 2>/dev/null || true
            systemctl start x-ui 2>/dev/null || true
            return 1
        fi
    fi

    mkdir -p "/root/cert/${target_dom}"
    local acme="/root/.acme.sh/acme.sh"

    # Try Let's Encrypt
    [[ "$silent" != "1" ]] && echo -e "${YELLOW}Let's Encrypt se cert request...${NC}"
    $acme --set-default-ca --server letsencrypt >/dev/null 2>&1
    local le_output
    le_output=$($acme --issue -d "$target_dom" --standalone --force 2>&1)
    local le_status=$?

    if [[ $le_status -ne 0 ]]; then
        if echo "$le_output" | grep -qi "rateLimited\|too many certificates\|rate limit"; then
            echo -e "${YELLOW}[WARNING] Let's Encrypt rate limit lag gaya. ZeroSSL try kar rahe hain...${NC}"
            # Register ZeroSSL account (free, no email required)
            $acme --set-default-ca --server zerossl >/dev/null 2>&1
            local zs_output
            zs_output=$($acme --issue -d "$target_dom" --standalone --force 2>&1)
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}[ERROR] ZeroSSL se bhi cert nahi bana.${NC}"
                echo "$zs_output" | tail -20
                systemctl start nginx 2>/dev/null || true
                systemctl start x-ui 2>/dev/null || true
                return 1
            fi
        else
            echo -e "${RED}[ERROR] Let's Encrypt cert fail hua.${NC}"
            echo "$le_output" | tail -20
            systemctl start nginx 2>/dev/null || true
            systemctl start x-ui 2>/dev/null || true
            return 1
        fi
    fi

    # Install cert files
    $acme --install-cert -d "$target_dom" \
        --fullchain-file "$cert_path" \
        --key-file "$key_path" >/dev/null 2>&1

    systemctl start nginx 2>/dev/null || true
    systemctl start x-ui 2>/dev/null || true

    # Verify cert is valid
    if [[ -f "$cert_path" ]] && openssl x509 -in "$cert_path" -noout -subject >/dev/null 2>&1; then
        local expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo -e "${GREEN}[OK] SSL cert valid hai: ${target_dom} (Expiry: ${expiry})${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Cert file invalid hai!${NC}"
        rm -f "$cert_path" "$key_path"
        return 1
    fi
}

install_3xui_panel() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - FULL AUTO INSTALL (3X-UI + SSH) ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}Sirf domain do, baaki sab AUTOMATIC!${NC}"
    echo -e "${GREEN}Username: admin | Password: zaini123 | Port: 8443${NC}"
    echo -e "${CYAN}====================================================${NC}\n"

    # ===== PRE-CHECK: INTERNET & DNS =====
    echo -e "${BLUE}[PRE-CHECK] Internet aur DNS check...${NC}"
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Internet connection nahi hai!${NC}"
        echo -e "${YELLOW}Fix karein:${NC}"
        echo -e "  1) DNS set karein: echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
        echo -e "  2) IPv6 disable karein agar IPv6 fail ho raha ho"
        echo -e "  3) VPS provider se internet issue check karein"
        press_any_key
        return
    fi
    if ! getent hosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARNING] DNS slow/fail ho raha hai. Google DNS set kar rahe hain...${NC}"
        rm -f /etc/resolv.conf
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
    # Prefer IPv4 for curl/wget on broken IPv6 VPS
    if ! curl -s4 --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARNING] IPv4 GitHub access fail. IPv6 disable kar rahe hain...${NC}"
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Internet aur DNS theek hain.${NC}\n"

    # ===== STEP 1: DOMAIN =====
    local current_dom=$(get_domain)
    if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
        echo -e "${YELLOW}${BOLD}[STEP 1] Domain chahiye (SIRF YEH DIYA HAI APKO)${NC}"
        read -rp "Apna subdomain daalein (e.g. vpn.example.com): " new_dom
        if [[ -z "$new_dom" ]]; then
            echo -e "${RED}Domain khaali nahi chhod sakte! Install cancel.${NC}"
            press_any_key
            return
        elif [[ "$new_dom" != *.* ]]; then
            echo -e "${RED}'${new_dom}' valid domain nahi hai (e.g. sub.example.com). Install cancel.${NC}"
            press_any_key
            return
        fi
        mkdir -p /etc/zainuxbrand
        echo "$new_dom" > /etc/zainuxbrand/domain.conf
        current_dom="$new_dom"
        echo -e "${GREEN}[OK] Domain save: $current_dom${NC}\n"
    else
        echo -e "${GREEN}[STEP 1] Domain already set: $current_dom${NC}"
        read -rp "Change karna hai? (Enter = no): " new_dom
        if [[ -n "$new_dom" ]]; then
            if [[ "$new_dom" != *.* ]]; then
                echo -e "${RED}'${new_dom}' valid domain nahi hai. Purana domain use ho raha hai.${NC}"
            else
                echo "$new_dom" > /etc/zainuxbrand/domain.conf
                current_dom="$new_dom"
            fi
        fi
        echo -e "${GREEN}[OK] Domain: $current_dom${NC}\n"
    fi

    # ===== STEP 2: DNS CHECK =====
    echo -e "${BLUE}[STEP 2] DNS check...${NC}"
    local dns_ip=$(getent hosts "$current_dom" 2>/dev/null | awk '{print $1}' | head -1)
    local vps_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null)
    if [[ -n "$dns_ip" && -n "$vps_ip" ]]; then
        if [[ "$dns_ip" == "$vps_ip" ]]; then
            echo -e "${GREEN}[OK] DNS sahi: $current_dom -> $vps_ip${NC}"
        else
            echo -e "${YELLOW}[WARNING] DNS ($dns_ip) != VPS ($vps_ip)${NC}"
            echo -e "${YELLOW}SSL cert nahi banega jab tak DNS sahi nahi. Install continue...${NC}"
        fi
    else
        echo -e "${YELLOW}[SKIP] DNS/IP check nahi ho saka. Continue...${NC}"
    fi

    # ===== STEP 3: INSTALL SSH VPN SYSTEM (if not installed) =====
    echo -e "\n${BLUE}[STEP 3] SSH VPN system check...${NC}"
    ensure_base_packages || {
        echo -e "${RED}[ERROR] Base packages install nahi ho sake. Install cancel.${NC}"
        press_any_key
        return
    }
    if ! command -v dropbear &>/dev/null || ! dpkg -l nginx 2>/dev/null | grep -q "^ii"; then
        echo -e "${YELLOW}SSH/NGINX system install nahi hai. Auto-install ho raha hai...${NC}"
        install_all_components
    else
        echo -e "${GREEN}[OK] SSH + Nginx system already installed.${NC}"
    fi

    # ===== STEP 4: INSTALL 3X-UI PANEL (auto credentials) =====
    echo -e "\n${BLUE}[STEP 4] 3X-UI Panel install (auto: admin/zaini123/8443)...${NC}"
    if command -v x-ui &>/dev/null; then
        echo -e "${GREEN}[OK] 3X-UI already installed.${NC}"
    else
        echo -e "${YELLOW}Required packages update/install ho rahe hain...${NC}"
        if ! apt-get update -y; then
            echo -e "${RED}[ERROR] apt-get update fail hua!${NC}"
            echo -e "${YELLOW}Try karein: apt-get clean && apt-get update -o Acquire::ForceIPv4=true${NC}"
            press_any_key
            return
        fi
        if ! apt-get install -y curl wget socat dnsutils; then
            echo -e "${RED}[ERROR] Packages install nahi ho sake (curl/wget/socat/dnsutils)!${NC}"
            press_any_key
            return
        fi

        echo -e "${YELLOW}3X-UI install script download ho raha hai...${NC}"
        rm -f /tmp/3xui-install.sh
        if command -v curl &>/dev/null; then
            curl -4 -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o /tmp/3xui-install.sh
        else
            wget -4 -q https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -O /tmp/3xui-install.sh
        fi

        if [[ ! -s /tmp/3xui-install.sh ]]; then
            echo -e "${RED}[ERROR] 3X-UI install script download nahi hui!${NC}"
            echo -e "${YELLOW}Internet/DNS check karein. Agar Iran/China/Pakistan block ho raha ho to VPN use karein.${NC}"
            press_any_key
            return
        fi

        echo -e "${YELLOW}3X-UI install ho raha hai (30-60 seconds)...${NC}"
        # Run with piped answers: y=yes customize, 8443=port, admin=user, zaini123=pass
        printf 'y\n8443\nadmin\nzaini123\n' | bash /tmp/3xui-install.sh 2>&1
        rm -f /tmp/3xui-install.sh
        # Ensure settings are set correctly (override in case piped input failed)
        if [[ -f /usr/local/x-ui/x-ui ]]; then
            /usr/local/x-ui/x-ui setting -username admin -password zaini123 -port 8443 2>/dev/null
            systemctl restart x-ui 2>/dev/null
            echo -e "${GREEN}[OK] 3X-UI installed!${NC}"
        else
            echo -e "${RED}[ERROR] 3X-UI install fail hua. /usr/local/x-ui/x-ui nahi mila.${NC}"
            press_any_key
            return
        fi
    fi

    # ===== STEP 5: BBR SPEED BOOST =====
    echo -e "\n${BLUE}[STEP 5] BBR speed boost...${NC}"
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
        echo -e "${GREEN}[OK] BBR enabled.${NC}"
    else
        echo -e "${GREEN}[OK] BBR already enabled.${NC}"
    fi

    # ===== STEP 6: FIREWALL =====
    echo -e "\n${BLUE}[STEP 6] Firewall ports...${NC}"
    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp 2>/dev/null
        ufw allow 80/tcp 2>/dev/null
        ufw allow 443/tcp 2>/dev/null
        ufw allow 109/tcp 2>/dev/null
        ufw allow 447/tcp 2>/dev/null
        ufw allow 8443/tcp 2>/dev/null
        ufw allow 2053/tcp 2>/dev/null
        ufw --force enable 2>/dev/null
        echo -e "${GREEN}[OK] Ports: 22, 80, 443, 109, 447, 2053, 8443${NC}"
    else
        echo -e "${YELLOW}[SKIP] UFW not installed. Cloud firewall bhi check karein.${NC}"
    fi

    # ===== STEP 7: SSL CERTIFICATE =====
    echo -e "\n${BLUE}[STEP 7] SSL Certificate...${NC}"
    if [[ -f "/root/cert/${current_dom}/fullchain.pem" ]] && openssl x509 -in "/root/cert/${current_dom}/fullchain.pem" -noout -subject >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] SSL cert already valid exists.${NC}"
    else
        issue_ssl_acme "$current_dom"
    fi

    # ===== STEP 8: TERMINAL ACCOUNT CREATOR + CONFIG =====
    echo -e "\n${BLUE}[STEP 8] Terminal Account Creator setup...${NC}"
    install_xui_helper
    # Auto-save config (no manual input needed)
    mkdir -p /etc/zainuxbrand
    cat > /etc/zainuxbrand/xui.conf << XUICONF
PANEL_USER="admin"
PANEL_PASS="zaini123"
PANEL_PORT="8443"
PANEL_DOMAIN="$current_dom"
CERT_PATH="/root/cert/${current_dom}/fullchain.pem"
KEY_PATH="/root/cert/${current_dom}/privkey.pem"
XUICONF
    chmod 600 /etc/zainuxbrand/xui.conf 2>/dev/null
    systemctl restart x-ui 2>/dev/null

    # ===== DONE =====
    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}       FULL AUTO INSTALL COMPLETE!                   ${NC}"
    echo -e "${GREEN}       (Sirf domain diya, baaki sab khud)             ${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo -e " Domain     : ${CYAN}$current_dom${NC}"
    echo -e " Panel Port : ${CYAN}8443${NC}"
    echo -e " Username   : ${CYAN}admin${NC}"
    echo -e " Password   : ${CYAN}zaini123${NC}"
    echo -e " Cert Path  : ${CYAN}/root/cert/${current_dom}/fullchain.pem${NC}"
    echo -e " Key Path   : ${CYAN}/root/cert/${current_dom}/privkey.pem${NC}"
    echo -e "${GREEN}----------------------------------------------------${NC}"
    echo -e "${YELLOW}AB BAS:${NC}"
    echo -e "  ${CYAN}Option 10${NC} se account banao (VLESS/VMess/Trojan)"
    echo -e "  Sirf naam do, link khud ban jayega!"
    echo -e "  DarkTunnel me paste -> Connect!"
    echo -e "${GREEN}====================================================${NC}"
    press_any_key
}

install_xui_helper() {
    cat << 'PY_EOF' > /usr/local/bin/xui-helper.py
#!/usr/bin/env python3
import urllib.request
import urllib.parse
import json
import ssl
import sys
import os
import uuid
import sqlite3
import re
import base64
import time

CONFIG_FILE = "/etc/zainuxbrand/xui.conf"
XUI_DB = "/etc/x-ui/x-ui.db"

def load_config():
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        for line in open(CONFIG_FILE):
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k] = v
    return cfg

def get_db_setting(key):
    if not os.path.exists(XUI_DB):
        return ""
    try:
        conn = sqlite3.connect(XUI_DB)
        c = conn.cursor()
        c.execute("SELECT value FROM settings WHERE key=?", (key,))
        row = c.fetchone()
        conn.close()
        return row[0] if row else ""
    except Exception:
        return ""

def get_web_base_path():
    bp = get_db_setting("webBasePath")
    if not bp:
        return ""
    if not bp.startswith("/"):
        bp = "/" + bp
    bp = bp.rstrip("/")
    return bp

def get_panel_port():
    p = get_db_setting("webPort")
    return p or "8443"

def make_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

def http_post(url, data, cookies=None):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    if cookies:
        req.add_header("Cookie", cookies)
    ctx = make_ssl_context()
    try:
        resp = urllib.request.urlopen(req, context=ctx, timeout=40)
        ck = resp.headers.get_all("Set-Cookie") or []
        text = resp.read().decode("utf-8", errors="ignore")
        parts = []
        for c in ck:
            m = re.match(r"\s*([^=]+=[^;]+)", c)
            if m:
                parts.append(m.group(1).strip())
        return resp.status, text, "; ".join(parts)
    except urllib.error.HTTPError as e:
        ck = e.headers.get_all("Set-Cookie") or []
        text = e.read().decode("utf-8", errors="ignore")
        parts = []
        for c in ck:
            m = re.match(r"\s*([^=]+=[^;]+)", c)
            if m:
                parts.append(m.group(1).strip())
        return e.code, text, "; ".join(parts)
    except Exception as e:
        return 0, str(e), ""

def login(base, web_base, username, password):
    url = base + web_base + "/login"
    status, body, cookie = http_post(url, {"username": username, "password": password})
    return status, body, cookie

def get_used_ports():
    used = set()
    try:
        import subprocess
        out = subprocess.check_output(["ss", "-tlnp"], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            m = re.search(r":(\d+)\s", line)
            if m:
                used.add(int(m.group(1)))
    except Exception:
        pass
    return used

def pick_port(preferred=443):
    used = get_used_ports()
    if preferred not in used:
        return preferred
    for p in [2083, 2087, 2096, 8444, 8445, 8446, 8447, 8448, 8449, 8450]:
        if p not in used:
            return p
    for p in range(30000, 35000):
        if p not in used:
            return p
    return 443

def gen_uuid():
    return str(uuid.uuid4())

def gen_sub_id():
    return uuid.uuid4().hex[:16]

def build_vless_settings(client_uuid, email, ip_limit, total_gb, expiry_time):
    return {
        "clients": [{
            "id": client_uuid,
            "email": email,
            "limitIp": ip_limit,
            "totalGB": total_gb,
            "expiryTime": expiry_time,
            "enable": True,
            "tgId": "",
            "subId": gen_sub_id(),
            "reset": 0
        }],
        "decryption": "none",
        "fallbacks": []
    }

def build_vmess_settings(client_uuid, email, ip_limit, total_gb, expiry_time):
    return {
        "clients": [{
            "id": client_uuid,
            "alterId": 0,
            "email": email,
            "limitIp": ip_limit,
            "totalGB": total_gb,
            "expiryTime": expiry_time,
            "enable": True,
            "tgId": "",
            "subId": gen_sub_id(),
            "reset": 0
        }],
        "disableInsecureEncryption": False
    }

def build_trojan_settings(password, email, ip_limit, total_gb, expiry_time):
    return {
        "clients": [{
            "password": password,
            "email": email,
            "limitIp": ip_limit,
            "totalGB": total_gb,
            "expiryTime": expiry_time,
            "enable": True,
            "tgId": "",
            "subId": gen_sub_id(),
            "reset": 0
        }],
        "fallbacks": []
    }

def build_tls_settings(domain, cert_path, key_path):
    return {
        "serverName": domain,
        "minVersion": "1.2",
        "maxVersion": "1.3",
        "cipherSuites": "",
        "rejectUnknownSni": False,
        "certificates": [{
            "certificateFile": cert_path,
            "keyFile": key_path,
            "ocspStapling": 3600,
            "oneTimeLoading": False,
            "usage": "encipherment",
            "buildChain": False
        }],
        "alpn": ["h2", "http/1.1"],
        "settings": {
            "allowInsecure": False,
            "fingerprint": "chrome"
        }
    }

def build_stream_grpc(domain, cert, key, service="tunnel"):
    return {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": build_tls_settings(domain, cert, key),
        "grpcSettings": {
            "serviceName": service,
            "multiMode": False,
            "idleTimeout": 60
        }
    }

def build_stream_ws(domain, cert, key, path="/tunnel"):
    return {
        "network": "ws",
        "security": "tls",
        "tlsSettings": build_tls_settings(domain, cert, key),
        "wsSettings": {
            "path": path,
            "headers": {}
        }
    }

SNIFFING = {"enabled": True, "destOverride": ["http", "tls", "quic"]}

def create_inbound(base, web_base, cookie, protocol, port, settings, stream, remark):
    url = base + web_base + "/panel/inbound/add"
    data = {
        "enable": "true",
        "listen": "",
        "port": str(port),
        "protocol": protocol,
        "settings": json.dumps(settings),
        "streamSettings": json.dumps(stream),
        "remark": remark,
        "sniffing": json.dumps(SNIFFING),
    }
    status, body, _ = http_post(url, data, cookies=cookie)
    return status, body

def url_encode(s):
    return urllib.parse.quote(s, safe="")

def gen_vless_link(client_uuid, domain, port, transport, sni, service_or_path, remark):
    params = []
    if transport == "grpc":
        params.append("type=grpc")
        params.append("serviceName=" + service_or_path)
    else:
        params.append("type=ws")
        params.append("path=" + url_encode(service_or_path))
        params.append("host=" + domain)
    params.append("security=tls")
    params.append("sni=" + sni)
    params.append("fp=chrome")
    query = "&".join(params)
    return f"vless://{client_uuid}@{domain}:{port}?{query}#{url_encode(remark)}"

def gen_vmess_link(client_uuid, domain, port, transport, sni, service_or_path, remark):
    obj = {
        "v": "2",
        "ps": remark,
        "add": domain,
        "port": str(port),
        "id": client_uuid,
        "aid": "0",
        "scy": "auto",
        "net": transport,
        "type": "none",
        "host": domain,
        "path": service_or_path,
        "tls": "tls",
        "sni": sni,
    }
    encoded = base64.b64encode(json.dumps(obj).encode()).decode()
    return "vmess://" + encoded

def gen_trojan_link(password, domain, port, transport, sni, service_or_path, remark):
    params = []
    if transport == "grpc":
        params.append("type=grpc")
        params.append("serviceName=" + service_or_path)
    else:
        params.append("type=ws")
        params.append("path=" + url_encode(service_or_path))
        params.append("host=" + domain)
    params.append("security=tls")
    params.append("sni=" + sni)
    params.append("fp=chrome")
    query = "&".join(params)
    return f"trojan://{url_encode(password)}@{domain}:{port}?{query}#{url_encode(remark)}"

def do_create(protocol, transport, domain, cert, key, port_choice, base, web_base, cookie):
    remark = input("  Account/Remark naam (e.g. user1): ").strip() or f"user-{int(time.time())}"
    try:
        days = input("  Expiry days (0=unlimited, default 0): ").strip() or "0"
        days = int(days)
    except:
        days = 0
    try:
        ip_limit = input("  IP limit (0=unlimited, default 0): ").strip() or "0"
        ip_limit = int(ip_limit)
    except:
        ip_limit = 0
    try:
        gb_limit = input("  Data limit GB (0=unlimited, default 0): ").strip() or "0"
        gb_limit = float(gb_limit)
    except:
        gb_limit = 0

    expiry_time = int((time.time() + days * 86400) * 1000) if days > 0 else 0
    total_gb = int(gb_limit * 1024 * 1024 * 1024) if gb_limit > 0 else 0

    client_uuid = gen_uuid()
    service = "tunnel"
    path = "/tunnel"

    if protocol == "vless":
        settings = build_vless_settings(client_uuid, remark, ip_limit, total_gb, expiry_time)
        if transport == "grpc":
            stream = build_stream_grpc(domain, cert, key, service)
            link = gen_vless_link(client_uuid, domain, port_choice, "grpc", domain, service, remark)
        else:
            stream = build_stream_ws(domain, cert, key, path)
            link = gen_vless_link(client_uuid, domain, port_choice, "ws", domain, path, remark)
    elif protocol == "vmess":
        settings = build_vmess_settings(client_uuid, remark, ip_limit, total_gb, expiry_time)
        if transport == "grpc":
            stream = build_stream_grpc(domain, cert, key, service)
            link = gen_vmess_link(client_uuid, domain, port_choice, "grpc", domain, service, remark)
        else:
            stream = build_stream_ws(domain, cert, key, path)
            link = gen_vmess_link(client_uuid, domain, port_choice, "ws", domain, path, remark)
    elif protocol == "trojan":
        trojan_pass = gen_uuid()
        settings = build_trojan_settings(trojan_pass, remark, ip_limit, total_gb, expiry_time)
        if transport == "grpc":
            stream = build_stream_grpc(domain, cert, key, service)
            link = gen_trojan_link(trojan_pass, domain, port_choice, "grpc", domain, service, remark)
        else:
            stream = build_stream_ws(domain, cert, key, path)
            link = gen_trojan_link(trojan_pass, domain, port_choice, "ws", domain, path, remark)
    else:
        print("Unknown protocol")
        sys.exit(1)

    status, body = create_inbound(base, web_base, cookie, protocol, port_choice, settings, stream, remark)
    print("\n" + "=" * 55)
    ok = False
    msg = ""
    try:
        resp = json.loads(body)
        ok = resp.get("success", False)
        msg = resp.get("msg", "")
    except:
        ok = (str(status) == "200")
        msg = body[:200]

    if ok:
        print("  ACCOUNT CREATED BY ZAINUXBRAND")
        print("=" * 55)
        print(f"  Protocol  : {protocol.upper()} + {transport.upper()} + TLS")
        print(f"  Domain    : {domain}")
        print(f"  Port      : {port_choice}")
        print(f"  Remark    : {remark}")
        print(f"  Expiry    : {days} days" + (" (unlimited)" if days == 0 else ""))
        print(f"  IP Limit  : {ip_limit}" + (" (unlimited)" if ip_limit == 0 else ""))
        print(f"  Data Limit: {gb_limit} GB" + (" (unlimited)" if gb_limit == 0 else ""))
        print("-" * 55)
        print("  CONFIG LINK (DarkTunnel me paste karein):")
        print("  " + link)
        print("-" * 55)
        print("  Upar wala link copy karo -> DarkTunnel -> Connect!")
    else:
        print("  ERROR: Inbound create nahi hua")
        print("  " + str(msg))
    print("=" * 55)

def do_list(base, web_base, cookie):
    url = base + web_base + "/panel/inbound/list"
    status, body, _ = http_post(url, {}, cookies=cookie)
    try:
        resp = json.loads(body)
        inbounds = resp.get("data", {}).get("obj", []) or resp.get("obj", [])
        if not inbounds:
            print("\n  Koi inbound nahi mila.")
            return
        print("\n" + "=" * 60)
        print("  X-UI INBOUNDS LIST")
        print("=" * 60)
        for ib in inbounds:
            print(f"  ID:{ib.get('id')} | {ib.get('remark')} | port:{ib.get('port')} | {ib.get('protocol')} | enable:{ib.get('enable')}")
        print("=" * 60)
    except Exception as e:
        print("Parse error:", e, body[:200])

def do_delete(base, web_base, cookie, inbound_id):
    url = base + web_base + f"/panel/inbound/del/{inbound_id}"
    status, body, _ = http_post(url, {}, cookies=cookie)
    print("Delete result:", status, body[:200])

def main():
    if len(sys.argv) < 2:
        print("Usage: xui-helper.py <command>")
        print("Commands: create-vless-grpc, create-vless-ws, create-vmess-grpc,")
        print("          create-vmess-ws, create-trojan-grpc, create-trojan-ws,")
        print("          list, delete <id>")
        sys.exit(1)

    cmd = sys.argv[1]
    cfg = load_config()
    username = cfg.get("PANEL_USER", "admin")
    password = cfg.get("PANEL_PASS", "")
    domain = cfg.get("PANEL_DOMAIN", "") or cfg.get("DOMAIN", "")
    port = cfg.get("PANEL_PORT", "") or get_panel_port()
    cert = cfg.get("CERT_PATH", f"/root/cert/{domain}/fullchain.pem")
    key = cfg.get("KEY_PATH", f"/root/cert/{domain}/privkey.pem")

    if not password:
        print("ERROR: Panel password set nahi. Pehle menu se 3X-UI config karein.")
        sys.exit(1)
    if not domain:
        print("ERROR: Domain set nahi. Menu option 2 se domain set karein.")
        sys.exit(1)

    base = f"https://localhost:{port}"
    web_base = get_web_base_path()

    status, body, cookie = login(base, web_base, username, password)
    if not cookie:
        status, body, cookie = login(base, "", username, password)
    if not cookie:
        print("ERROR: Panel login fail.", status)
        print(body[:300])
        sys.exit(1)

    if cmd.startswith("create-"):
        parts = cmd.split("-")
        protocol = parts[1] if len(parts) > 1 else ""
        transport = parts[2] if len(parts) > 2 else "grpc"
        proto_map = {"vless": "vless", "vmess": "vmess", "trojan": "trojan"}
        trans_map = {"grpc": "grpc", "ws": "ws"}
        protocol = proto_map.get(protocol, protocol)
        transport = trans_map.get(transport, transport)
        port_choice = pick_port(443)
        print(f"\n  Selected: {protocol.upper()} + {transport.upper()} + TLS")
        print(f"  Auto Port: {port_choice}")
        do_create(protocol, transport, domain, cert, key, port_choice, base, web_base, cookie)
    elif cmd == "list":
        do_list(base, web_base, cookie)
    elif cmd == "delete":
        if len(sys.argv) < 3:
            print("Usage: xui-helper.py delete <id>")
            sys.exit(1)
        do_delete(base, web_base, cookie, sys.argv[2])
    else:
        print("Unknown command:", cmd)

if __name__ == "__main__":
    main()
PY_EOF
    chmod +x /usr/local/bin/xui-helper.py
}

setup_xui_config() {
    mkdir -p /etc/zainuxbrand
    local conf_file="/etc/zainuxbrand/xui.conf"
    local current_dom=$(get_domain)

    if [[ -f "$conf_file" ]]; then
        . "$conf_file"
    fi

    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   3X-UI PANEL CONFIG (Terminal Access Setup)        ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${YELLOW}Panel ke login credentials chahiye (terminal se account banane ke liye).${NC}"
    echo -e "${YELLOW}Jo 3X-UI install ke waqt set kiya tha wohi daalein.${NC}\n"

    local p_user="${PANEL_USER:-admin}"
    read -rp "Panel Username [$p_user]: " new_user
    [[ -z "$new_user" ]] && new_user="$p_user"

    local p_pass=""
    while [[ -z "$p_pass" ]]; do
        read -rp "Panel Password: " p_pass
        [[ -z "$p_pass" ]] && echo -e "${RED}Password khaali nahi chhod sakte!${NC}"
    done

    local p_port="${PANEL_PORT:-8443}"
    read -rp "Panel Port [$p_port]: " new_port
    [[ -z "$new_port" ]] && new_port="$p_port"

    local p_dom="${PANEL_DOMAIN:-$current_dom}"
    [[ -z "$p_dom" || "$p_dom" == "No Domain Set" ]] && p_dom=""
    if [[ -z "$p_dom" ]]; then
        read -rp "Domain (e.g. sub.example.com): " p_dom
    else
        read -rp "Domain [$p_dom]: " new_dom
        [[ -z "$new_dom" ]] && new_dom="$p_dom" || p_dom="$new_dom"
    fi

    local cert_path="/root/cert/${p_dom}/fullchain.pem"
    local key_path="/root/cert/${p_dom}/privkey.pem"

    cat > "$conf_file" << EOF
PANEL_USER="$new_user"
PANEL_PASS="$p_pass"
PANEL_PORT="$new_port"
PANEL_DOMAIN="$p_dom"
CERT_PATH="$cert_path"
KEY_PATH="$key_path"
EOF

    chmod 600 "$conf_file"

    echo -e "\n${GREEN}[SUCCESS] 3X-UI config saved!${NC}"
    echo -e "${CYAN}Domain     : $p_dom${NC}"
    echo -e "${CYAN}Panel Port : $new_port${NC}"
    echo -e "${CYAN}Cert Path  : $cert_path${NC}"

    install_xui_helper
    echo -e "${GREEN}[OK] xui-helper installed. Ab terminal se accounts banaye ja sakte hain!${NC}"
    press_any_key
}

xui_account_menu() {
    if ! command -v x-ui &>/dev/null; then
        echo -e "${RED}[ERROR] 3X-UI install nahi hai! Pehle Option 9 se install karein.${NC}"
        press_any_key
        return
    fi

    if [[ ! -f /usr/local/bin/xui-helper.py ]]; then
        echo -e "${YELLOW}xui-helper nahi mila, ab install ho raha hai...${NC}"
        install_xui_helper
    fi

    if [[ ! -f /etc/zainuxbrand/xui.conf ]]; then
        echo -e "${YELLOW}Pehle panel config set karna hoga...${NC}"
        setup_xui_config
    fi

    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}    ${PANEL_NAME} - X-UI ACCOUNT CREATOR            ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " ${GREEN}VLESS (VLESS + TLS):${NC}"
        echo -e "  1) VLESS + gRPC + SSL/TLS"
        echo -e "  2) VLESS + WebSocket + SSL/TLS"
        echo -e " ${GREEN}VMess:${NC}"
        echo -e "  3) VMess + gRPC + SSL/TLS"
        echo -e "  4) VMess + WebSocket + SSL/TLS"
        echo -e " ${GREEN}Trojan:${NC}"
        echo -e "  5) Trojan + gRPC + SSL/TLS"
        echo -e "  6) Trojan + WebSocket + SSL/TLS"
        echo -e " ${CYAN}--------------------${NC}"
        echo -e "  7) List All X-UI Accounts"
        echo -e "  8) Delete X-UI Account (by ID)"
        echo -e "  9) Re-Configure Panel Access"
        echo -e " 10) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Select [1-10]: " x_opt

        case $x_opt in
            1) python3 /usr/local/bin/xui-helper.py create-vless-grpc ;;
            2) python3 /usr/local/bin/xui-helper.py create-vless-ws ;;
            3) python3 /usr/local/bin/xui-helper.py create-vmess-grpc ;;
            4) python3 /usr/local/bin/xui-helper.py create-vmess-ws ;;
            5) python3 /usr/local/bin/xui-helper.py create-trojan-grpc ;;
            6) python3 /usr/local/bin/xui-helper.py create-trojan-ws ;;
            7) python3 /usr/local/bin/xui-helper.py list ;;
            8)
                python3 /usr/local/bin/xui-helper.py list
                read -rp "Inbound ID to delete: " del_id
                [[ -n "$del_id" ]] && python3 /usr/local/bin/xui-helper.py delete "$del_id"
                ;;
            9) setup_xui_config ;;
            10) return ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
        press_any_key
    done
}

fix_and_diagnose() {
    while true; do
        clear
        local current_dom=$(get_domain)
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}    ${PANEL_NAME} - FIX & DIAGNOSE (Live Debug)    ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " Domain: ${YELLOW}${current_dom}${NC}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        echo -e " ${GREEN}Quick Status:${NC}"
        echo -e "  x-ui running  : $([ -n \"$(systemctl is-active x-ui 2>/dev/null)\" ] && systemctl is-active x-ui 2>/dev/null || echo 'NOT INSTALLED')"
        echo -e "  dropbear       : $([ -n \"$(systemctl is-active dropbear 2>/dev/null)\" ] && systemctl is-active dropbear 2>/dev/null || echo 'NOT INSTALLED')"
        echo -e "  nginx          : $([ -n \"$(systemctl is-active nginx 2>/dev/null)\" ] && systemctl is-active nginx 2>/dev/null || echo 'NOT INSTALLED')"
        local cert_status="MISSING"
        if [[ -f "/root/cert/${current_dom}/fullchain.pem" ]] && openssl x509 -in "/root/cert/${current_dom}/fullchain.pem" -noout -subject >/dev/null 2>&1; then
            cert_status="VALID"
        elif [[ -f "/root/cert/${current_dom}/fullchain.pem" ]]; then
            cert_status="EXISTS BUT INVALID"
        fi
        echo -e "  SSL cert       : ${cert_status}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        echo -e " ${YELLOW}0) AUTO FIX EVERYTHING (Common issues auto repair)${NC}"
        echo -e " 1) Restart ALL Services (x-ui + dropbear + nginx)"
        echo -e " 2) Check Listening Ports (ss -tlnp)"
        echo -e " 3) Check DNS Resolution"
        echo -e " 4) Check SSL Certificate Details"
        echo -e " 5) Fix/Re-issue SSL Certificate"
        echo -e " 6) Fix Panel Credentials (reset admin/zaini123)"
        echo -e " 7) Fix Panel Port (change to 8443)"
        echo -e " 8) Check Firewall Rules (ufw)"
        echo -e " 9) View x-ui Logs (last 30 lines)"
        echo -e "10) Fix Nginx Config (regenerate)"
        echo -e "11) Check VPS IP + Connectivity"
        echo -e "12) Full System Diagnostic Report"
        echo -e "13) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Select [0-13]: " fix_opt

        case $fix_opt in
            0)
                echo -e "\n${BLUE}=== AUTO FIX EVERYTHING START ===${NC}"
                local current_dom=$(get_domain)
                # 1) Fix DNS
                echo -e "${YELLOW}[1/7] DNS fix...${NC}"
                rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" > /etc/resolv.conf
                echo "nameserver 1.1.1.1" >> /etc/resolv.conf
                # 2) Install missing base packages (nginx, dropbear, openssh, etc.)
                echo -e "${YELLOW}[2/7] Missing packages install...${NC}"
                ensure_base_packages || true
                # 3) Fix dropbear + OpenSSH
                echo -e "${YELLOW}[3/7] SSH services fix...${NC}"
                fix_dropbear_core
                # 4) Regenerate nginx config
                echo -e "${YELLOW}[4/7] Nginx config fix...${NC}"
                apply_nginx_config
                # 5) Fix panel credentials & port
                echo -e "${YELLOW}[5/7] Panel credentials/port fix...${NC}"
                if [[ -f /usr/local/x-ui/x-ui ]]; then
                    /usr/local/x-ui/x-ui setting -username admin -password zaini123 -port 8443 2>/dev/null
                fi
                # 6) Re-issue SSL
                echo -e "${YELLOW}[6/7] SSL cert fix...${NC}"
                if [[ "$current_dom" != "No Domain Set" && -n "$current_dom" ]]; then
                    issue_ssl_acme "$current_dom" 1
                    # Re-apply nginx with new cert
                    apply_nginx_config
                fi
                # 7) Restart all
                echo -e "${YELLOW}[7/7] Restarting all services...${NC}"
                systemctl restart nginx 2>/dev/null || true
                systemctl restart x-ui 2>/dev/null || true
                systemctl restart ws-proxy 2>/dev/null || true
                systemctl restart autokill 2>/dev/null || true
                echo -e "${GREEN}[OK] Auto fix complete!${NC}"
                ;;
            1)
                echo -e "\n${BLUE}Restarting ALL services...${NC}"
                systemctl restart x-ui 2>/dev/null && echo -e "${GREEN}[OK] x-ui restarted${NC}" || echo -e "${YELLOW}[SKIP] x-ui not installed${NC}"
                systemctl restart dropbear 2>/dev/null && echo -e "${GREEN}[OK] dropbear restarted${NC}" || echo -e "${YELLOW}[SKIP] dropbear not installed${NC}"
                systemctl restart nginx 2>/dev/null && echo -e "${GREEN}[OK] nginx restarted${NC}" || echo -e "${YELLOW}[SKIP] nginx not installed${NC}"
                systemctl restart ws-proxy 2>/dev/null && echo -e "${GREEN}[OK] ws-proxy restarted${NC}" || echo -e "${YELLOW}[SKIP]${NC}"
                systemctl restart autokill 2>/dev/null && echo -e "${GREEN}[OK] autokill restarted${NC}" || echo -e "${YELLOW}[SKIP]${NC}"
                ;;
            2)
                echo -e "\n${CYAN}=== Listening Ports ===${NC}"
                ss -tlnp 2>/dev/null | grep -E "x-ui|xray|dropbear|nginx|python|2096|8443|443|80|109|447|2082" || ss -tlnp 2>/dev/null
                ;;
            3)
                local current_dom=$(get_domain)
                if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
                    echo -e "${RED}Domain set nahi hai! Option 2 se set karein.${NC}"
                else
                    echo -e "\n${CYAN}=== DNS Check for $current_dom ===${NC}"
                    local dns_ip=$(getent hosts "$current_dom" 2>/dev/null | awk '{print $1}' | head -1)
                    local vps_ip=$(curl -s4 ifconfig.me 2>/dev/null)
                    echo -e " Domain     : $current_dom"
                    echo -e " DNS IP     : ${dns_ip:-NOT RESOLVING}"
                    echo -e " VPS IP     : ${vps_ip:-CANNOT DETERMINE}"
                    if [[ -n "$dns_ip" && -n "$vps_ip" && "$dns_ip" == "$vps_ip" ]]; then
                        echo -e "${GREEN}[OK] DNS sahi hai!${NC}"
                    else
                        echo -e "${RED}[ERROR] DNS != VPS IP!${NC}"
                        echo -e "${YELLOW}Apne domain provider mein A record set karein: $vps_ip${NC}"
                    fi
                fi
                ;;
            4)
                local current_dom=$(get_domain)
                if [[ -f "/root/cert/${current_dom}/fullchain.pem" ]]; then
                    echo -e "\n${CYAN}=== SSL Cert Details ===${NC}"
                    openssl x509 -in "/root/cert/${current_dom}/fullchain.pem" -noout -subject -dates -issuer 2>/dev/null
                    echo -e "\n${GREEN}Cert Path : /root/cert/${current_dom}/fullchain.pem${NC}"
                    echo -e "${GREEN}Key Path  : /root/cert/${current_dom}/privkey.pem${NC}"
                else
                    echo -e "${RED}SSL cert nahi mila! Option 5 se re-issue karein.${NC}"
                fi
                ;;
            5)
                local current_dom=$(get_domain)
                if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
                    echo -e "${RED}Domain set nahi hai! Pehle Option 2 se set karein.${NC}"
                else
                    issue_ssl_acme "$current_dom"
                fi
                ;;
            6)
                echo -e "\n${BLUE}Panel credentials reset (admin/zaini123)...${NC}"
                if [[ -f /usr/local/x-ui/x-ui ]]; then
                    /usr/local/x-ui/x-ui setting -username admin -password zaini123 2>/dev/null
                    systemctl restart x-ui 2>/dev/null
                    echo -e "${GREEN}[OK] Username: admin | Password: zaini123${NC}"
                else
                    echo -e "${RED}3X-UI install nahi hai! Option 9 se install karein.${NC}"
                fi
                ;;
            7)
                echo -e "\n${BLUE}Panel port change to 8443...${NC}"
                if [[ -f /usr/local/x-ui/x-ui ]]; then
                    /usr/local/x-ui/x-ui setting -port 8443 2>/dev/null
                    systemctl restart x-ui 2>/dev/null
                    echo -e "${GREEN}[OK] Panel port: 8443${NC}"
                else
                    echo -e "${RED}3X-UI install nahi hai!${NC}"
                fi
                ;;
            8)
                echo -e "\n${CYAN}=== Firewall Rules ===${NC}"
                if command -v ufw &>/dev/null; then
                    ufw status verbose 2>/dev/null
                    echo -e "\n${YELLOW}Cloud provider (UpCloud/Hetzner/etc) ka dashboard bhi check karein!${NC}"
                else
                    echo -e "${YELLOW}UFW not installed. Cloud provider firewall check karein.${NC}"
                fi
                ;;
            9)
                echo -e "\n${CYAN}=== x-ui Logs (last 30) ===${NC}"
                journalctl -u x-ui --no-pager -n 30 2>/dev/null || echo -e "${YELLOW}Logs nahi mil rahe.${NC}"
                ;;
            10)
                echo -e "\n${BLUE}Nginx config regenerate...${NC}"
                if [[ -f /etc/nginx/conf.d/vpn.conf ]]; then
                    echo -e "${YELLOW}Existing config backup ho raha hai...${NC}"
                    cp /etc/nginx/conf.d/vpn.conf /etc/nginx/conf.d/vpn.conf.bak 2>/dev/null
                fi
                apply_nginx_config
                echo -e "${GREEN}[OK] Nginx config regenerated.${NC}"
                ;;
            11)
                echo -e "\n${CYAN}=== VPS IP & Connectivity ===${NC}"
                local vps_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null)
                echo -e " VPS Public IP : ${vps_ip:-CANNOT DETERMINE}"
                echo -e " Internet      : $([ -n \"$vps_ip\" ] && echo 'OK' || echo 'NO INTERNET')"
                if command -v x-ui &>/dev/null; then
                    echo -e " x-ui          : INSTALLED"
                    systemctl is-active x-ui 2>/dev/null | xargs -I{} echo -e " x-ui status   : {}"
                else
                    echo -e " x-ui          : NOT INSTALLED"
                fi
                ;;
            12)
                echo -e "\n${CYAN}====================================================${NC}"
                echo -e "${YELLOW}        FULL SYSTEM DIAGNOSTIC REPORT               ${NC}"
                echo -e "${CYAN}====================================================${NC}"
                local current_dom=$(get_domain)
                local vps_ip=$(curl -s4 ifconfig.me 2>/dev/null || echo "UNKNOWN")
                echo -e "\n${GREEN}--- VPS INFO ---${NC}"
                echo -e " Public IP     : $vps_ip"
                echo -e " OS            : $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
                echo -e " Uptime        : $(uptime 2>/dev/null | awk -F'load' '{print $1}' | xargs)"
                echo -e " Domain        : $current_dom"
                echo -e "\n${GREEN}--- SERVICES ---${NC}"
                for svc in x-ui dropbear nginx ws-proxy autokill; do
                    local st=$(systemctl is-active "$svc" 2>/dev/null)
                    printf " %-15s : %s\n" "$svc" "${st:-NOT INSTALLED}"
                done
                echo -e "\n${GREEN}--- PORTS ---${NC}"
                ss -tlnp 2>/dev/null | grep -E "8443|443|80|109|447|2082|22" | awk '{print $4, $6}' | sed 's/users://'
                echo -e "\n${GREEN}--- SSL ---${NC}"
                if [[ -f "/root/cert/${current_dom}/fullchain.pem" ]]; then
                    echo -e " Cert EXISTS   : /root/cert/${current_dom}/fullchain.pem"
                    openssl x509 -in "/root/cert/${current_dom}/fullchain.pem" -noout -enddate 2>/dev/null | xargs -I{} echo -e " Expiry        : {}"
                else
                    echo -e " Cert          : MISSING"
                fi
                echo -e "\n${GREEN}--- DNS ---${NC}"
                if [[ "$current_dom" != "No Domain Set" && -n "$current_dom" ]]; then
                    local dns_ip=$(getent hosts "$current_dom" 2>/dev/null | awk '{print $1}' | head -1)
                    echo -e " Resolves to   : ${dns_ip:-FAILED}"
                    [[ "$dns_ip" == "$vps_ip" ]] && echo -e " DNS Match      : OK" || echo -e " DNS Match      : MISMATCH!"
                fi
                echo -e "\n${GREEN}--- FIREWALL ---${NC}"
                if command -v ufw &>/dev/null; then
                    ufw status 2>/dev/null | head -20
                else
                    echo -e " UFW           : NOT INSTALLED"
                fi
                echo -e "\n${CYAN}====================================================${NC}"
                ;;
            13) return ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
        press_any_key
    done
}

while true; do
    clear
    CURRENT_DOM=$(get_domain)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e " Custom Path  : ${YELLOW}${CUSTOM_PATH}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) Auto Install System Components"
    echo -e " 2) Add / Change Domain Name"
    echo -e " 3) Issue SSL Certificate"
    echo -e " 4) Manage Accounts (Add/Delete/Renew/Limits)"
    echo -e " 5) Check Status & Ports"
    echo -e " 6) Set / Edit SSH Banner"
    echo -e " 7) Fix SSH WS & WS+SSL Connection"
    echo -e " 8) Setup / Manage Telegram Bot"
    echo -e " 9) ${GREEN}FULL AUTO Install (Sirf Domain Do - 3X-UI + SSH + SSL)${NC}"
    echo -e " 10) Manage X-UI Accounts (VLESS/VMess/Trojan) - Terminal se!"
    echo -e " 11) ${RED}FULL UNINSTALL (VPS Fresh Reset - Sab Delete)${NC}"
    echo -e " 12) ${YELLOW}Fix & Diagnose Issues (0=Auto Fix Everything)${NC}"
    echo -e " 13) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-13]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) user_menu ;;
        5) status_check ;;
        6) set_banner ;;
        7) fix_websocket ;;
        8) setup_telegram_bot ;;
        9) install_3xui_panel ;;
        10) xui_account_menu ;;
        11) uninstall_panel ;;
        12) fix_and_diagnose ;;
        13) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
