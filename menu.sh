#!/usr/bin/env bash
# ZAINU X BRAND PREMIUM VPN SCRIPT
# Ubuntu 22.04/24.04 | sudo bash zainu-x-menu.sh
set -Eeuo pipefail
umask 077
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
APP=/etc/zainu-x; OUT=/root/ZAINU-X-CLIENTS; DB=$APP/accounts.tsv; CFG=$APP/settings; CREDS=$APP/creds
XRAY=/usr/local/etc/xray; XCONF=$XRAY/config.json; NCONF=/etc/nginx/sites-available/zainu-x.conf
mkdir -p "$APP" "$OUT"; chmod 700 "$APP" "$OUT"; touch "$DB"; chmod 600 "$DB"
C='\033[1;36m'; M='\033[1;35m'; G='\033[1;32m'; R='\033[1;31m'; N='\033[0m'
ok(){ echo -e "${G}[+]${N} $*"; }; bad(){ echo -e "${R}[!]${N} $*" >&2; }
load(){ [[ -f $CFG ]] && source "$CFG"; DOMAIN=${DOMAIN:-}; EMAIL=${EMAIL:-}; SSH_PORT=${SSH_PORT:-22}; DROPBEAR_PORT=${DROPBEAR_PORT:-2222}; }
save(){ printf 'DOMAIN=%q\nEMAIL=%q\nSSH_PORT=%q\nDROPBEAR_PORT=%q\n' "$DOMAIN" "$EMAIL" "$SSH_PORT" "$DROPBEAR_PORT" >"$CFG"; chmod 600 "$CFG"; }
head(){ clear 2>/dev/null || true; echo -e "${M}════════════════════════════════════════════${N}"; echo -e "${C}       ZAINU X BRAND PREMIUM VPN SCRIPT${N}"; echo -e "${M}════════════════════════════════════════════${N}"; }
valid(){ [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
setup_inputs(){ load; [[ $DOMAIN ]] || read -rp 'VPN subdomain: ' DOMAIN; [[ $EMAIL ]] || read -rp "Let's Encrypt email: " EMAIL; valid "$DOMAIN" || { bad 'Invalid domain'; return 1; }; save; }
install_packages(){ export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y curl ca-certificates nginx certbot openssl uuid-runtime jq openssh-server dropbear ufw fail2ban; }
setup_ssh(){ mkdir -p /etc/ssh/sshd_config.d; cat >/etc/ssh/sshd_config.d/99-zainu-x.conf <<EOF
Port $SSH_PORT
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t; systemctl enable --now ssh dropbear; if grep -q '^DROPBEAR_PORT=' /etc/default/dropbear; then sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=$DROPBEAR_PORT/" /etc/default/dropbear; else echo "DROPBEAR_PORT=$DROPBEAR_PORT" >>/etc/default/dropbear; fi; systemctl restart ssh dropbear; }
install_xray(){ command -v xray >/dev/null 2>&1 || bash <(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install; install -d -m 700 "$XRAY"; }
ssl(){ getent ahostsv4 "$DOMAIN" >/dev/null || { bad "DNS $DOMAIN does not resolve"; return 1; }; systemctl stop nginx 2>/dev/null || true; certbot certonly --standalone --agree-tos --non-interactive --email "$EMAIL" -d "$DOMAIN"; }
nginx(){ mkdir -p /var/www/html; printf '%s\n' '<h1>ZAINU X BRAND PREMIUM VPN</h1><p>Server online.</p>' >/var/www/html/index.html; cat >"$NCONF" <<EOF
server { listen 80; server_name $DOMAIN; location / { return 301 https://\$host\$request_uri; } }
server { listen 443 ssl http2; server_name $DOMAIN; ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem; location /zainuxbrand { proxy_pass http://127.0.0.1:10000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection upgrade; proxy_set_header Host \$host; } }
EOF
ln -sfn "$NCONF" /etc/nginx/sites-enabled/zainu-x.conf; rm -f /etc/nginx/sites-enabled/default; nginx -t; systemctl enable --now nginx; }
render(){ local clients=''; while IFS=$'\t' read -r type user secret ip gb days expiry; do [[ $type == xray && $secret ]] && clients+="{\"id\":\"$secret\",\"email\":\"$user\"},"; done <"$DB"; clients="${clients%,}"; [[ $clients ]] || { source "$CREDS" 2>/dev/null || true; clients="{\"id\":\"${UUID:-$(uuidgen)}\",\"email\":\"main\"}"; }; cat >"$XCONF" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":10000,"protocol":"vless","settings":{"clients":[$clients],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/zainuxbrand"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
xray run -test -config "$XCONF"; systemctl enable --now xray; systemctl restart xray; }
full(){ setup_inputs; install_packages; setup_ssh; install_xray; ssl; nginx; : >"$CREDS"; chmod 600 "$CREDS"; render; for p in "$SSH_PORT" "$DROPBEAR_PORT" 80 443; do ufw allow "$p"/tcp >/dev/null; done; ufw --force enable >/dev/null; ok 'Full setup completed'; }
ssh_account(){ local USER PASS IP GB DAYS EXP; read -rp 'SSH username: ' USER; [[ "$USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { bad 'Invalid username'; return; }; id "$USER" >/dev/null 2>&1 && { bad 'Username already exists'; return; }; read -rsp 'SSH password: ' PASS; echo; [[ -n "$PASS" ]] || { bad 'Password cannot be blank'; return; }; read -rp 'IP limit: ' IP; read -rp 'GB limit (0=unlimited): ' GB; read -rp 'Validity days: ' DAYS; [[ "$IP" =~ ^[1-9][0-9]*$ && "$GB" =~ ^[0-9]+$ && "$DAYS" =~ ^[1-9][0-9]*$ ]] || { bad 'IP/GB/days must be numeric'; return; }; EXP=$(date -d "+$DAYS days" +%Y-%m-%d); useradd -m -s /bin/bash -e "$EXP" "$USER"; printf '%s:%s\n' "$USER" "$PASS" | chpasswd; printf 'ssh\t%s\t%s\t%s\t%s\t%s\t%s\n' "$USER" "$PASS" "$IP" "$GB" "$DAYS" "$EXP" >>"$DB"; mkdir -p "$OUT/ssh-$USER"; cat >"$OUT/ssh-$USER/account.txt" <<EOF
ZAINU X BRAND PREMIUM VPN SCRIPT
TYPE: SSH / DROPBEAR
USERNAME: $USER
PASSWORD: $PASS
HOST/SNI: $DOMAIN
SSH PORT: $SSH_PORT
DROPBEAR PORT: $DROPBEAR_PORT
IP LIMIT: $IP
GB LIMIT: $GB
VALID UNTIL: $EXP
PAYLOAD/HOST: $DOMAIN
EOF
chmod 600 "$OUT/ssh-$USER/account.txt"; echo; cat "$OUT/ssh-$USER/account.txt"; ok 'SSH account created successfully'; }
xray_account(){ local USER IP GB DAYS EXP UUID; read -rp 'Xray username/label: ' USER; [[ "$USER" =~ ^[A-Za-z0-9_-]+$ ]] || { bad 'Invalid label'; return; }; read -rp 'IP limit: ' IP; read -rp 'GB limit (0=unlimited): ' GB; read -rp 'Validity days: ' DAYS; [[ "$IP" =~ ^[1-9][0-9]*$ && "$GB" =~ ^[0-9]+$ && "$DAYS" =~ ^[1-9][0-9]*$ ]] || { bad 'IP/GB/days must be numeric'; return; }; UUID=$(uuidgen); EXP=$(date -d "+$DAYS days" +%Y-%m-%d); printf 'xray\t%s\t%s\t%s\t%s\t%s\t%s\n' "$USER" "$UUID" "$IP" "$GB" "$DAYS" "$EXP" >>"$DB"; render; cat >"$OUT/xray-$USER.txt" <<EOF
ZAINU X BRAND PREMIUM VPN SCRIPT
TYPE: XRAY VLESS WS TLS
USERNAME: $USER
UUID: $UUID
HOST/SNI: $DOMAIN
WS PATH: /zainuxbrand
IP LIMIT: $IP
GB LIMIT: $GB
VALID UNTIL: $EXP
VLESS LINK: vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=%2Fzainuxbrand#$USER
EOF
chmod 600 "$OUT/xray-$USER.txt"; echo; cat "$OUT/xray-$USER.txt"; ok 'Xray account created successfully'; }
status(){ systemctl --no-pager --full status nginx xray dropbear ssh | sed -n '1,100p' || true; ls -la "$OUT"; }
restart_services(){ systemctl restart nginx xray dropbear ssh; ok 'Services restarted'; }
renew_ssl(){ systemctl stop nginx 2>/dev/null || true; certbot renew; systemctl start nginx; systemctl restart xray; }
change_domain(){ load; read -rp 'New domain: ' DOMAIN; read -rp "Let's Encrypt email: " EMAIL; valid "$DOMAIN" || { bad 'Invalid domain'; return; }; save; ssl; nginx; render; ok 'Domain and SNI updated'; }
list_accounts(){ printf '%s\n' 'TYPE USER SECRET IP GB DAYS EXPIRY'; column -t -s $'\t' "$DB" 2>/dev/null || cat "$DB"; }
delete_account(){ local USER; read -rp 'Username/label: ' USER; sed -i -E "/^[^[:space:]]+[[:space:]]+$USER[[:space:]]/d" "$DB"; id "$USER" >/dev/null 2>&1 && userdel -r "$USER" 2>/dev/null || true; rm -f "$OUT/ssh-$USER/account.txt" "$OUT/xray-$USER.txt"; render 2>/dev/null || true; ok 'Account removed if it existed'; }
uninstall_all(){ read -rp 'Type UNINSTALL to continue: ' X; [[ "$X" == UNINSTALL ]] || { echo cancelled; return; }; while IFS=$'\t' read -r type user _; do [[ "$type" == ssh ]] && id "$user" >/dev/null 2>&1 && userdel -r "$user" 2>/dev/null || true; done <"$DB"; systemctl disable --now xray nginx dropbear fail2ban 2>/dev/null || true; rm -f /etc/nginx/sites-enabled/zainu-x.conf "$NCONF" /etc/ssh/sshd_config.d/99-zainu-x.conf; rm -rf "$APP" "$OUT" "$XRAY" /var/www/html/index.html; apt-get purge -y xray dropbear certbot nginx fail2ban 2>/dev/null || true; apt-get autoremove -y 2>/dev/null || true; for p in 2222; do ufw delete allow "$p"/tcp 2>/dev/null || true; done; systemctl restart ssh 2>/dev/null || true; echo 'ZAINU X uninstall complete'; }
menu(){ while true; do head; echo '1) Full setup/repair'; echo '2) Create SSH/Dropbear account'; echo '3) Create Xray account'; echo '4) List accounts'; echo '5) Delete account'; echo '6) Status/client files'; echo '7) Restart services'; echo '8) Renew SSL'; echo '9) Change domain'; echo '10) Full uninstall'; echo '0) Exit'; read -rp 'Select option: ' n; case "$n" in 1) full;; 2) ssh_account;; 3) xray_account;; 4) list_accounts;; 5) delete_account;; 6) status;; 7) restart_services;; 8) renew_ssl;; 9) change_domain;; 10) uninstall_all;; 0) exit 0;; *) bad 'Invalid option';; esac; read -rp 'Press Enter...' _; done; }
load; menu
