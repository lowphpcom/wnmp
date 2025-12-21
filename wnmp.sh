#!/usr/bin/env bash
# WNMP Setup Script
# Copyright (C) 2025 wnmp.org
# Website: https://wnmp.org
# License: GNU General Public License v3.0 (GPLv3)
# Version: 1.18

set -euo pipefail

set +u
: "${DEBUGINFOD_IMA_CERT_PATH:=}"
set -u
for v in WSL_DISTRO_NAME WSL_INTEROP WSLENV; do
  eval "export $v=\"\${$v:-}\""
done

export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Please run as root"
  exit 1
fi

LOGFILE="/root/logwnmp.log"

if [[ -f "$LOGFILE" ]]; then
  mv -f "$LOGFILE" "${LOGFILE%.*}-$(date +%F-%H%M%S).log"
fi

export LC_BYOBU="${LC_BYOBU-}"

export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:${PATH}"

if [[ -t 1 && -z "${WNMP_UNDER_SCRIPT:-}" ]]; then
  if command -v script >/dev/null 2>&1; then
    export WNMP_UNDER_SCRIPT=1
    exec script -qef -c "env PATH=\"$PATH\" SYSTEMD_COLORS=1 SYSTEMD_PAGER=cat bash --noprofile --norc '$0' $*" "$LOGFILE"
  else
    echo "[WARN] 'script' not found; continuing without logging to file."
  fi
fi



red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue()   { echo -e "\033[36m$*\033[0m"; }

echo
green  "============================================================"
green  " [init] WNMP one-click installer started"
green  " [init] https://wnmp.org"
green  " [init] Logs saved to: ${LOGFILE}"
green  " [init] Start time: $(date '+%F %T')"
green  " [init] Version: 1.18"
green  "============================================================"
echo
sleep 1

usage() {
  cat <<'USAGE'
Usage:
  bash wnmp.sh               # Install normally
  bash wnmp.sh status        # Show status
  bash wnmp.sh sshkey        # SSH key login
  bash wnmp.sh webdav        # Add WebDAV account
  bash wnmp.sh vhost         # Create virtual host (with certificate)
  bash wnmp.sh tool          # Kernel/Network tuning only
  bash wnmp.sh restart       # Restart services
  bash wnmp.sh remove        # Uninstall
  bash wnmp.sh renginx       # Uninstallnginx
  bash wnmp.sh rephp         # Uninstallphp
  bash wnmp.sh remariadb     # Uninstallmariadb
  bash wnmp.sh wslinit       # Wsl open SSH Server
  bash wnmp.sh fixsshd       # Self-check sshd and attempt to repair
  bash wnmp.sh -h|--help     # Show help
USAGE
}

fixsshd() {
  echo "=========================================="
  echo "[+] Starting to repair SSHD configuration and host key permissions..."
  echo "=========================================="
  set -euo pipefail

  # 1) Fix permissions for /etc/ssh and its include directory
  mkdir -p /etc/ssh/sshd_config.d
  chown -R root:root /etc/ssh
  chmod 755 /etc/ssh /etc/ssh/sshd_config.d
  find /etc/ssh/sshd_config.d -type f -exec chown root:root {} \; -exec chmod 0644 {} \;
  echo "[OK] Directory permissions have been fixed."

  # 2) Remove potentially corrupted HostKeys, regenerate them, and fix permissions
  rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub || true
  ssh-keygen -A >/dev/null
  chown root:root /etc/ssh/ssh_host_*_key
  chmod 600 /etc/ssh/ssh_host_*_key
  echo "[OK] SSH HostKeys have been regenerated."

  # 3) Validate sshd configuration
  echo "[*] Checking if sshd configuration is valid..."
  if ! /usr/sbin/sshd -t; then
    echo "[!] sshd configuration test failed. Showing detailed log:"
    /usr/sbin/sshd -t -E /tmp/sshd-check.log || true
    tail -n +1 /tmp/sshd-check.log
    echo "=========================================="
    echo "[X] sshd configuration still contains errors. Please check the log above."
    echo "=========================================="
    return 1
  fi
  echo "[OK] sshd configuration test passed."

  # 4) Reload and restart SSH service
  systemctl daemon-reload
  systemctl restart ssh || systemctl restart sshd || true
  echo "[OK] sshd restart attempted. Current status:"
  systemctl status ssh --no-pager --full || systemctl status sshd --no-pager --full || true
  echo "=========================================="
  echo "[✓] SSH repair process completed."
  echo "=========================================="
}



wslinit(){

  

export DEBIAN_FRONTEND=noninteractive
apt update
apt -y full-upgrade

echo "[4/7] Install common tools and openssh-server ..."
apt install -y \
  build-essential \
  ca-certificates \
  curl wget unzip git cmake pkg-config \
  htop net-tools \
  openssh-server

install -d -m 0755 -o root -g root /run/sshd

ssh-keygen -A

update-ca-certificates || true

echo "[5/7] Configure SSH: Allow root login + password login ..."

SSHD_CFG="/etc/ssh/sshd_config"

set_sshd_option() {
  local key="$1"
  local value="$2"
  if grep -qE "^[#[:space:]]*${key}\b" "$SSHD_CFG"; then
    sed -i "s/^[#[:space:]]*${key}.*/${key} ${value}/" "$SSHD_CFG"
  else
    echo "${key} ${value}" >>"$SSHD_CFG"
  fi
}

set_sshd_option "PermitRootLogin" "yes"
set_sshd_option "PasswordAuthentication" "yes"
set_sshd_option "PermitEmptyPasswords" "no"
set_sshd_option "PubkeyAuthentication" "yes"

echo "[6/7] Restart the SSH service ..."

if command -v service >/dev/null 2>&1; then
  service sshd restart || true
fi


if command -v systemctl >/dev/null 2>&1; then
  systemctl enable sshd >/dev/null 2>&1 || true
  systemctl restart sshd >/dev/null 2>&1 || true
fi

echo "[7/7] Set the root password (please enter the new password twice as prompted) ..."
passwd root

echo "[7.1/7] Set the default user to root (write to /etc/wsl.conf) ..."

cat >/etc/wsl.conf <<'EOF'
[boot]
systemd=true
[user]
default=root
EOF
mkdir -p /run/sshd && sudo chmod 755 /run/sshd
ssh-keygen -A
/usr/sbin/sshd -t &&  systemctl restart sshd && systemctl status sshd --no-pager

mkdir -p /run/sshd && sudo chmod 755 /run/sshd
ssh-keygen -A
systemctl restart sshd

fixsshd || echo "[WARN] SSHD self-check failed. Please run 'bash wnmp.sh fixsshd' manually to view the details."

echo
echo "================= Complete ================="
echo "[OK] System upgraded, common tools and openssh-server installed."
echo "[OK] SSH root + password login enabled."
echo
echo "Quick tips:"
echo "  1) In WSL2, if ssh isn't running, start it manually:"
echo "       systemctl start sshd"
echo
echo "  2) To test connection locally (within WSL):"
echo "       ssh root@127.0.0.1"
echo
echo "  3) For cloud servers, use:"
echo "       ssh root@serverIP"
echo
echo "  4) WSL initialization is complete. You must use the startup script and restart your hardware computer once for it to function properly."
echo
echo "  5) Please restart your Windows 11 computer. Only after restarting should you run bash wnmp.sh again within the Linux subsystem to actually install the web environment."
echo
echo "========================================"

}




IS_LAN=1
PUBLIC_IP=""

is_lan() {
  local ip="" wan=""

  _pick_best_ipv4() {
    local x private=""

    for x in $(hostname -I 2>/dev/null); do
      [[ -z "$x" ]] && continue
      [[ "$x" =~ : ]] && continue        # 跳过 IPv6
      [[ "$x" =~ ^127\. ]] && continue

      if [[ "$x" =~ ^10\. ]] || \
         [[ "$x" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
         [[ "$x" =~ ^192\.168\. ]] || \
         [[ "$x" =~ ^169\.254\. ]]; then
        [[ -z "$private" ]] && private="$x"
        continue
      fi
      echo "$x"
      return 0
    done


    [[ -n "$private" ]] && echo "$private" || echo ""
  }

  _get_public_ipv4() {
    local out=""

    if command -v curl >/dev/null 2>&1; then
      out="$(curl -4fsS --max-time 3 https://1.1.1.1/cdn-cgi/trace 2>/dev/null \
        | awk -F= '/^ip=/{print $2; exit}')"
      [[ -z "$out" ]] && out="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(curl -4fsS --max-time 3 https://ifconfig.me/ip 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(curl -4fsS --max-time 3 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(curl -4fsS --max-time 3 https://icanhazip.com 2>/dev/null | tr -d '\r\n ')"
    elif command -v wget >/dev/null 2>&1; then
      out="$(wget -4qO- --timeout=3 https://1.1.1.1/cdn-cgi/trace 2>/dev/null \
        | awk -F= '/^ip=/{print $2; exit}')"
      [[ -z "$out" ]] && out="$(wget -4qO- --timeout=3 https://api.ipify.org 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(wget -4qO- --timeout=3 https://ifconfig.me/ip 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(wget -4qO- --timeout=3 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n ')"
      [[ -z "$out" ]] && out="$(wget -4qO- --timeout=3 https://icanhazip.com 2>/dev/null | tr -d '\r\n ')"
    fi

    if [[ "$out" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$out"
    else
      echo ""
    fi
  }

  ip="$(_pick_best_ipv4)"

  if [[ -z "$ip" ]]; then
    IS_LAN=1
    PUBLIC_IP="$(_get_public_ipv4)"
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=""
    return 0
  fi

  if [[ "$ip" =~ ^10\. ]] || \
     [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
     [[ "$ip" =~ ^192\.168\. ]] || \
     [[ "$ip" =~ ^169\.254\. ]]; then
    IS_LAN=1
    wan="$(_get_public_ipv4)"
    PUBLIC_IP="${wan:-}"
  else
    IS_LAN=0
    PUBLIC_IP="$ip"
  fi

  return 0
}



is_lan




service_exists() {
  local svc="$1"
  systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"
}


status() {

  for svc in nginx php-fpm mariadb; do
    if service_exists "$svc"; then
      echo "▶ ${svc} status:"
      systemctl --no-pager status "$svc"
      echo
    else
      echo "⚠️  ${svc} service not found, skipped."
    fi
  done

  exit 0
}
restart() {

  for svc in nginx php-fpm mariadb; do
    if service_exists "$svc"; then
      echo "▶ restarting ${svc}..."
      systemctl restart "$svc"
      systemctl --no-pager status "$svc"
      echo
    else
      echo "⚠️  ${svc} service not found, skipped."
    fi
  done

  echo "Services restarted"
  exit 0
}




webdav() {
  local domain user pass passwd_file ans

  read -rp "Enable WebDAV？[y/N] " ans
  ans="${ans:-N}"
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "[webdav] Skipped."
    return 0
  fi

  while :; do
    read -rp "If the site has multiple domain names, please enter the final redirect domain. (e.g., site.example.com):" domain
    [[ -n "$domain" ]] && break
    echo "[webdav][WARN] Domain cannot be empty。"
  done


  read -rp "Enable public directory by default? (No)[y/N] " ans
  ans="${ans:-N}"
  local enable_public=0
  [[ "$ans" =~ ^[Yy]$ ]] && enable_public=1


  local VHOST_DIR="/usr/local/nginx/vhost"
  local domain_lc conf_path backup tmp
  domain_lc="$(echo "$domain" | tr '[:upper:]' '[:lower:]')"
  conf_path="$VHOST_DIR/${domain_lc}.conf"
  if [[ ! -f "$conf_path" && "$domain_lc" =~ ^www\. ]]; then
    conf_path="$VHOST_DIR/${domain_lc#www.}.conf"
  fi
  if [[ ! -f "$conf_path" ]]; then
    echo "[webdav][ERROR] Config not found：$VHOST_DIR/${domain_lc}.conf OR ${domain_lc#www.}.conf"
    return 1
  fi

  local NGINX_BIN=""
  if command -v nginx >/dev/null 2>&1; then
    NGINX_BIN="$(command -v nginx)"
  elif [[ -x /usr/local/nginx/sbin/nginx ]]; then
    NGINX_BIN="/usr/local/nginx/sbin/nginx"
  elif [[ -x /usr/sbin/nginx ]]; then
    NGINX_BIN="/usr/sbin/nginx"
  else
    echo "[webdav][ERROR] Nginx binary not found; consider ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx"
    return 1
  fi

  backup="${conf_path}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$conf_path" "$backup" || { echo "[webdav][ERROR] Backup failed：$backup"; return 1; }

 
  insert_once() { 
    local _conf="$1" _line="$2" _tmp
    grep -qE "^[[:space:]]*${_line//\//\\/}[[:space:]]*$" "$_conf" && return 0
    _tmp="$(mktemp)"
    awk -v INS="    ${_line}" '
      BEGIN { depth=0; inserted=0 }
      {
        line=$0
        if (depth==1 && inserted==0 && line ~ /^[[:space:]]*index[[:space:]]+index\.html;[[:space:]]*$/) {
          print line; print INS; inserted=1; next
        }
        if (depth==1 && inserted==0 && line ~ /^[[:space:]]*location[[:space:]]+/) {
          print INS; inserted=1; print line; next
        }
        print line
        open_cnt  = gsub(/{/,"&")
        close_cnt = gsub(/}/,"&")
        depth += open_cnt - close_cnt
      }
    ' "$_conf" > "$_tmp"

    if ! grep -qE "^[[:space:]]*${_line//\//\\/}[[:space:]]*$" "$_tmp"; then
      awk -v INS="    ${_line}" '
        BEGIN{depth=0; done=0}
        {
          line=$0; print line
          open_cnt  = gsub(/{/,"&"); close_cnt = gsub(/}/,"&")
          next_depth = depth + open_cnt - close_cnt
          if (!done && depth==1 && next_depth==0) { print INS; done=1 }
          depth = next_depth
        }
      ' "$_tmp" > "${_tmp}.2" && mv "${_tmp}.2" "$_tmp"
    fi
    mv "$_tmp" "$_conf"
  }


  if [[ $enable_public -eq 1 ]]; then
  
    sed -i '/^[[:space:]]*include[[:space:]]\+enable-php\.conf;[[:space:]]*$/d' "$conf_path"
    echo "[webdav] Removed include enable-php.conf;（Disable PHP execution）"
    insert_once "$conf_path" "include download.conf;"
    echo "[webdav] Ensured include download.conf;"
  else

    sed -i '/^[[:space:]]*include[[:space:]]\+download\.conf;[[:space:]]*$/d' "$conf_path"
    echo "[webdav] Removed include download.conf;"
    insert_once "$conf_path" "include enable-php.conf;"
    echo "[webdav] Ensured include enable-php.conf;"
  fi


  if "$NGINX_BIN" -t; then
    if systemctl >/dev/null 2>&1; then
      systemctl reload nginx 2>/dev/null || "$NGINX_BIN" -s reload
    else
      "$NGINX_BIN" -s reload
    fi
    echo "[webdav] ✅ Config applied。"
  else
    echo "[webdav][ERROR] nginx -t Failed，Rolling back to：$backup"
    cp -a "$backup" "$conf_path" >/dev/null 2>&1 || true
    return 1
  fi


  local passwd_dir="/home/passwd"
  mkdir -p "$passwd_dir"
  passwd_file="${passwd_dir}/.${domain}"

  while :; do
    read -rp "Enter WebDAV username：" user
    [[ -n "$user" ]] && break
    echo "[webdav][WARN] Username cannot be empty。"
  done

  read -rs -p "Enter WebDAV password：" pass; echo

  if [[ -f "$passwd_file" ]]; then
    echo "[webdav] Existing password file detected, appending account..."
    htpasswd -bB "$passwd_file" "$user" "$pass"
  else
    echo "[webdav] No password file found, creating..."
    htpasswd -cbB "$passwd_file" "$user" "$pass"
  fi
 
  chown www:www "$passwd_file" 2>/dev/null || true
  chmod 640 "$passwd_file" 2>/dev/null || true

  echo "[webdav] ✅ Account written：$user -> $passwd_file"
}






vhost() {
if [[ "$IS_LAN" -eq 1 ]]; then
red "[env] Detected a LAN environment, certificate issuance will be skipped."
read -rp "Do you want to force certificate issuance? [y/N] " ans
ans="${ans:-N}"
if [[ "$ans" =~ [Yy]$ ]]; then
  green "[env] Forced certificate issuance enabled."
  IS_LAN=0
else
  red "[env] Certificate issuance remains skipped."
fi
else
green "[env] Public network detected, certificate issuance is available."
fi
  if ! (echo $BASH_VERSION >/dev/null 2>&1); then
    echo "[vhost][ERROR] Please run this script with bash."; return 1
  fi
  set -euo pipefail

  local tmpl


if [[ "$IS_LAN" -eq 1 ]]; then
 tmpl=$(cat <<'EOF'
server{
    listen 80;
    server_name example;
    root  /home/wwwroot/default;
    index index.html index.php;

    error_page 403 = @e403;

    location @e403 {
        root html;
        internal;
        types { }
        default_type text/html;
        add_header Content-Type "text/html; charset=utf-8";  
        try_files /403.html =403;
    }

    error_page 502 504 404 = @e404;
    location @e404 {
        root html;
        internal;
        types { }
        default_type text/html;
        add_header Content-Type "text/html; charset=utf-8";
        try_files /404.html =404;
    }

    tcp_nopush on;
    tcp_nodelay on;
    include enable-php.conf;
    
    location ~* /(low)/                 { deny all; }
    location ~* ^/(upload|uploads)/.*\.php$ { deny all; }
    location ~* .*\.(log|sql|db|back|conf|cli|bak|env)$ { deny all; }
    location ~ /\.                      { deny all; access_log off; log_not_found off; }
    location = /favicon.ico             { access_log off; log_not_found off; expires max; try_files /favicon.ico =204; }
    location = /robots.txt              { allow all; access_log off; log_not_found off; }

    location ~* ^.+\.(apk|css|webp|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|pdf|txt|xml|json|mp4|webm|avi|mp3|zip|rar|tar|gz|xlsx|docx|bin|pcm)$ {
        access_log off;
        expires 1d;
        add_header Cache-Control "public";
        try_files $uri =404;
        location ~ \.(php|phtml|sh|bash|pl|py|exe)$ { deny all; }
    }
    
    location / {
        try_files $uri $uri/ @lowphp;
    }
    location @lowphp {
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://lowphp;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_connect_timeout 3s;
        proxy_send_timeout    30s;
        proxy_read_timeout    60s;
        
    }

   
    access_log off;
}
EOF
)
else
  tmpl=$(cat <<'EOF'
server{
    listen 80;
    listen 443 ssl;
    http2 on;
    server_name example;
    root  /home/wwwroot/default;
    index index.html index.php;

    error_page 403 = @e403;

    location @e403 {
        root html;
        internal;
        types { }
        default_type text/html;
        add_header Content-Type "text/html; charset=utf-8";  
        try_files /403.html =403;
    }

    error_page 502 504 404 = @e404;
    location @e404 {
        root html;
        internal;
        types { }
        default_type text/html;
        add_header Content-Type "text/html; charset=utf-8";
        try_files /404.html =404;
    }
    tcp_nopush on;
    tcp_nodelay on;
    include enable-php.conf;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    ssl_certificate     /usr/local/nginx/ssl/default/cert.pem;
    ssl_certificate_key /usr/local/nginx/ssl/default/key.pem;
    ssl_trusted_certificate /usr/local/nginx/ssl/default/ca.pem;
    ssl_session_cache   shared:SSL:20m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!RC4:!3DES;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
   
    location ~* /(low)/                 { deny all; }
    location ~* ^/(upload|uploads)/.*\.php$ { deny all; }
    location ~* .*\.(log|sql|db|back|conf|cli|bak|env)$ { deny all; }
    location ~ /\.                      { deny all; access_log off; log_not_found off; }
    location = /favicon.ico             { access_log off; log_not_found off; expires max; try_files /favicon.ico =204; }
    location = /robots.txt              { allow all; access_log off; log_not_found off; }

    location ~* ^.+\.(apk|css|webp|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|pdf|txt|xml|json|mp4|webm|avi|mp3|zip|rar|tar|gz|xlsx|docx|bin|pcm)$ {
        access_log off;
        expires 1d;
        add_header Cache-Control "public";
        try_files $uri =404;
        location ~ \.(php|phtml|sh|bash|pl|py|exe)$ { deny all; }
    }
    
    location / {
        try_files $uri $uri/ @lowphp;
    }
    location @lowphp {
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://lowphp;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_connect_timeout 3s;
        proxy_send_timeout    30s;
        proxy_read_timeout    60s;
        
    }

    location = /webdav {
        return 301 /webdav/;
    }

    location ^~ /webdav/ {
        if ($server_port != 443) { return 403; }
        set $domain $host;
        if ($host ~* "^www\.(.+)$") {
            set $domain $1;
        }
        set $site_root /home/wwwroot/$domain;
        alias $site_root/;
       
        types { }

        default_type application/octet-stream;
        auth_basic "WebDAV Authentication";
        auth_basic_user_file /home/passwd/.$host;
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
        create_full_put_path on;
        dav_access user:rw group:rw all:r;
        dav_ext_lock zone=webdav_locks;
        
    }
    access_log off;
}
EOF
)
fi


  local vhost_dir="/usr/local/nginx/vhost"
  local webroot_base="/home/wwwroot"
  local owner="www:www"

  local acme_home="${ACME_HOME:-$HOME/.acme.sh}"
  local acme_bin=""
  if command -v acme.sh >/dev/null 2>&1; then
    acme_bin="$(command -v acme.sh)"
  elif [[ -x "$acme_home/acme.sh" ]]; then
    acme_bin="$acme_home/acme.sh"
  fi
  echo "[vhost][INFO] acme_bin: ${acme_bin:-<not found>}"
  echo "[vhost][INFO] ACME_HOME: ${acme_home}"


  local DOMAINS=()
  read -rp "Please enter the domain names to create (multiple entries allowed, separated by spaces).： " -a DOMAINS
  [[ ${#DOMAINS[@]} -gt 0 ]] || { echo "[vhost] No domain entered. Quitting."; return 1; }
  local _filtered=()
  local d
  for d in "${DOMAINS[@]}"; do
    d="$(echo -n "$d" | tr -d '[:space:]')"
    [[ -n "$d" ]] && _filtered+=("$d")
  done
  DOMAINS=("${_filtered[@]}")
  [[ ${#DOMAINS[@]} -gt 0 ]] || { echo "[vhost] No valid domains provided, exiting."; return 1; }

  local primary="${DOMAINS[0]}"
  local others=()
  [[ ${#DOMAINS[@]} -gt 1 ]] && others=("${DOMAINS[@]:1}")


  local issue_cert="n"
  local ans
  read -rp "Issue certificates for these domains now?[Y/n] " ans
  ans="${ans:-Y}"
  [[ "$ans" == [Yy] ]] && issue_cert="y"
  if [[ "$issue_cert" == "y" && -z "$acme_bin" ]]; then
    echo "[vhost][WARN] acme.sh not found, skipping certificate issuance."; issue_cert="n"
  fi

  if [[ "$IS_LAN" -eq 1 ]]; then
      echo "[env] This is an internal network environment; certificate requests will be skipped."; issue_cert="n"
  fi
  remove_old_redirects() { 
    sed -i '/# BEGIN AUTO-HTTPS-REDIRECT/,/# END AUTO-HTTPS-REDIRECT/d' "$1" || true
  }
  inject_after_server_name() { 
    awk -v SNIP="$2" 'BEGIN{inserted=0}{
      print $0
      if (inserted==0 && $0 ~ /server_name[ \t].*;/){ print SNIP; inserted=1 }
    }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  }
  update_ssl_paths_single_dir() { 
    local conf="$1"; local dir="$2"
    local cert="${dir}/cert.pem"; local key="${dir}/key.pem"; local ca="${dir}/ca.pem"
    sed -i \
      -e "s#ssl_certificate[[:space:]]\+/usr/local/nginx/ssl/default/cert.pem;#ssl_certificate     ${cert};#g" \
      -e "s#ssl_certificate_key[[:space:]]\+/usr/local/nginx/ssl/default/key.pem;#ssl_certificate_key ${key};#g" \
      -e "s#ssl_trusted_certificate[[:space:]]\+/usr/local/nginx/ssl/default/ca.pem;#ssl_trusted_certificate ${ca};#g" \
      "$conf"
    if ! grep -qE "ssl_certificate[[:space:]]+${cert//\//\\/};" "$conf"; then
      local _SSL_LINES
      _SSL_LINES="$(cat <<EOF
    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
    ssl_trusted_certificate ${$ca};
EOF
)"
      inject_after_server_name "$conf" "$_SSL_LINES"
    fi
  }
  strip_ssl_lines() {
    sed -i \
      -e '/^[[:space:]]*listen[[:space:]]\+443[[:space:]]\+ssl;[[:space:]]*$/d' \
      -e '/^[[:space:]]*http2 on;[[:space:]]*$/d' \
      -e '/^[[:space:]]*add_header[[:space:]]\+Strict-Transport-Security/d' \
      -e '/^[[:space:]]*ssl_certificate[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_certificate_key[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_trusted_certificate[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_session_timeout[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_session_cache[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_protocols[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_ciphers[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_prefer_server_ciphers[[:space:]]\+/d' \
      "$1"
  }
  ensure_https_core() {
    grep -q 'listen 443 ssl;' "$1" || sed -i 's/^ *listen 80;$/    listen 80;\n    listen 443 ssl;/' "$1"
    grep -q '^ *http2 on;' "$1" || inject_after_server_name "$1" "    http2 on;"
    grep -q 'Strict-Transport-Security' "$1" || inject_after_server_name "$1" '    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;'
  }

  local REDIR_WWW_SSL REDIR_PLAIN_SSL REDIR_WWW_NO_SSL
  REDIR_WWW_SSL="$(cat <<'EOF'
# BEGIN AUTO-HTTPS-REDIRECT
    if ($host !~* ^www\.) {
        return 301 https://www.$host$request_uri;
    }
    if ($server_port = 80 ) {
        return 301 https://$host$request_uri;
    }
# END AUTO-HTTPS-REDIRECT
EOF
)"
  REDIR_PLAIN_SSL="$(cat <<'EOF'
# BEGIN AUTO-HTTPS-REDIRECT
    if ($server_port = 80 ) {
        return 301 https://$host$request_uri;
    }
# END AUTO-HTTPS-REDIRECT
EOF
)"
  REDIR_WWW_NO_SSL="$(cat <<'EOF'
# BEGIN AUTO-HTTPS-REDIRECT
    if ($host !~* ^www\.) {
        return 301 http://www.$host$request_uri;
    }
# END AUTO-HTTPS-REDIRECT
EOF
)"


  local server_names=("$primary")
  [[ ${#others[@]} -gt 0 ]] && server_names+=("${others[@]}")
  local has_www_peer=0
  for d in "${server_names[@]}"; do
    [[ "$d" == www.* ]] && { has_www_peer=1; break; }
  done


  mkdir -p "$vhost_dir" "$webroot_base"
  local bare_primary="${primary#www.}"
  local site_root="${webroot_base}/${bare_primary}"
  local conf="${vhost_dir}/${primary}.conf"
  [[ -f "$conf" ]] && cp -f "$conf" "${conf}.$(date +%Y%m%d%H%M%S).bak"

  local server_name_line="server_name ${server_names[*]};"
  echo "$tmpl" | sed \
    -e "s/server_name[[:space:]]\+example;/${server_name_line//\//\\/}/" \
    -e "s#\(root[[:space:]]\+\)/home/wwwroot/default;#\1${site_root};#g" \
    > "$conf"

  mkdir -p "$site_root/.well-known/acme-challenge"
  chown -R "$owner" "$site_root"
  echo "[vhost] Generated config file：$conf"


  get_cf_token() {
    local token_file="$acme_home/account.conf"
    if [[ -n "${CF_Token:-}" ]]; then
      echo "$CF_Token"; return 0
    fi
    if [[ -f "$token_file" ]]; then
      local _t
      _t="$(grep -E "^SAVED_CF_Token=" "$token_file" | cut -d"'" -f2 || true)"
      [[ -z "$_t" ]] && _t="$(grep -E "^SAVED_CF_Key=" "$token_file" | cut -d"'" -f2 || true)"
      [[ -n "$_t" ]] && { echo "$_t"; return 0; }
    fi
    return 1
  }

  local ssl_dir="/usr/local/nginx/ssl/${primary}"
  local cert_success=0
  if [[ "$issue_cert" == "y" ]]; then
    bash "$acme_home/acme.sh" --set-default-ca --server letsencrypt || true
    read -rp "Have these domains pointed to this server IP? (type yes to confirm): " ans
    if [[ "${ans,,}" != "yes" ]]; then
      echo "[safe] Operation cancelled. No changes made."; return 0
    fi

    local CF_Token_val="" dns_cf_ok=0
    CF_Token_val="$(get_cf_token || true)"
    [[ -n "$CF_Token_val" && -f "$acme_home/dnsapi/dns_cf.sh" ]] && dns_cf_ok=1
    echo "[vhost][INFO] CF_Token: $( [[ -n "${CF_Token_val:-}" ]] && echo "${CF_Token_val:0:6}******" || echo "<none>" )"
    echo "[vhost][INFO] dns_cf.sh: $( [[ $dns_cf_ok -eq 1 ]] && echo found || echo missing )"

    mkdir -p "$ssl_dir"
    local -a args
    if [[ $dns_cf_ok -eq 1 ]]; then
      echo "[vhost][ISSUE] Issuing for all domains using dns_cf..."
      args=( --issue --server letsencrypt --dns dns_cf -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      CF_Token="$CF_Token_val" "$acme_bin" "${args[@]}" --keylength ec-256 --force|| true
    else
      echo "[vhost][ISSUE] Issuing for all domains using webroot..."
      args=( --issue --server letsencrypt -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      args+=( --webroot "$site_root" --keylength ec-256 --force )
      "$acme_bin" "${args[@]}" || true
    fi

    "$acme_bin" --install-cert -d "$primary" \
      --ecc \
      --key-file       "$ssl_dir/key.pem" \
      --fullchain-file "$ssl_dir/cert.pem" \
      --ca-file        "$ssl_dir/ca.pem" \
      --reloadcmd      "true" || true

    if [[ -s "$ssl_dir/key.pem" && -s "$ssl_dir/cert.pem" ]]; then
      cert_success=1
      echo "[vhost][OK] Certificate is ready：$primary -> $ssl_dir"
      ensure_https_core "$conf"
      update_ssl_paths_single_dir "$conf" "$ssl_dir"
    else
      echo "[vhost][WARN] Certificate issuance did not succeed and will be treated as no certificate requested." 
    fi
  fi

  remove_old_redirects "$conf"
  if [[ "$cert_success" -eq 1 ]]; then
    if [[ "$has_www_peer" -eq 1 ]]; then
      inject_after_server_name "$conf" "$REDIR_WWW_SSL"
      echo "[vhost][HTTPS] Injected: force www + single redirect (includes HTTP→HTTPS)"
    else
      inject_after_server_name "$conf" "$REDIR_PLAIN_SSL"
      echo "[vhost][HTTPS] Injected: HTTP→HTTPS redirect"
    fi
  else
    if [[ "$has_www_peer" -eq 1 ]]; then
       strip_ssl_lines "$conf"
       inject_after_server_name "$conf" "$REDIR_WWW_NO_SSL"
       echo "[vhost][HTTP] Injected: www normalization (HTTP only)"
    fi
   
  fi


  if /usr/local/nginx/sbin/nginx -t; then
    /usr/local/nginx/sbin/nginx -s reload || systemctl reload nginx
    echo "[vhost] Nginx reloaded."
  else
    echo "[vhost][ERROR] nginx configuration check failed."; return 1 
  fi

  if [[ "$cert_success" -eq 1 ]]; then
    webdav
  else
    echo "[vhost][INFO] Skip WebDAV (due to certificate not enabled/failed to issue)." 
  fi

  echo "[vhost] Done."
}





purge_nginx() {
  echo "Purging NGINX (if any)..."
  systemctl stop nginx 2>/dev/null || true
  systemctl disable nginx 2>/dev/null || true
  rm -f /etc/systemd/system/nginx.service
  systemctl daemon-reload || true
  rm -rf /usr/local/nginx /etc/nginx /var/log/nginx /home/wwwlogs/nginx_error.log \
         /usr/sbin/nginx /usr/bin/nginx /root/nginx-* /usr/local/src/nginx-*
}
purge_php() {
  echo "Purging PHP (if any)..."
  systemctl stop php-fpm 2>/dev/null || true
  systemctl disable php-fpm 2>/dev/null || true
  rm -f /etc/systemd/system/php-fpm.service
  systemctl daemon-reload || true

  rm -rf /usr/local/php /etc/php* /var/log/php* /var/run/php* \
         /usr/bin/php /usr/bin/phpize /usr/bin/php-config \
         /usr/local/bin/php* \
         /usr/local/lib/php \
         /usr/lib/php \
         /root/php-*/  /root/inotify* /root/php-*.tar.* /usr/local/src/php-* /root/swoole*

  apt purge -y 'php*' 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
}
purge_mariadb() {
  set -euo pipefail

  has_mariadb_service=0
  if systemctl list-unit-files | grep -qE '^(mariadb|mysql)\.service'; then
    has_mariadb_service=1
  fi

  has_mariadb_bins=0
  if command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1; then
    has_mariadb_bins=1
  fi

  has_mysql_datadir=0
  if [ -d /var/lib/mysql ] || [ -d /var/lib/mariadb ]; then
    has_mysql_datadir=1
  fi

  if [ "$has_mariadb_service" -eq 0 ] && [ "$has_mariadb_bins" -eq 0 ] && [ "$has_mysql_datadir" -eq 0 ]; then
    echo "[mariadb] No MariaDB components found — skipping backup and cleanup."
  else

    backup_done=0
    ts="$(date +%Y%m%d_%H%M%S)"
    backup_file="/home/all_databases_backup_${ts}.sql.gz"

    mysql_cmd_base=(mysql --connect-timeout=3 --protocol=SOCKET -uroot)
    mysqldump_cmd_base=(mysqldump --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)

    if [ -f /etc/my.cnf ]; then
      mysql_cmd_base=(mysql --defaults-file=/etc/my.cnf --connect-timeout=3)
      mysqldump_cmd_base=(mysqldump --defaults-file=/etc/my.cnf --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)
    fi

    if ! "${mysql_cmd_base[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
      mysql_cmd_base=(mysql -h127.0.0.1 -P3306 -uroot --connect-timeout=3)
      mysqldump_cmd_base=(mysqldump -h127.0.0.1 -P3306 -uroot --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)

      if [ -f /etc/my.cnf ]; then
        mysql_cmd_base=(mysql --defaults-file=/etc/my.cnf -h127.0.0.1 -P3306 --connect-timeout=3)
        mysqldump_cmd_base=(mysqldump --defaults-file=/etc/my.cnf -h127.0.0.1 -P3306 --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)
      fi
    fi

    if "${mysql_cmd_base[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
      echo "[backup] Detected a running MariaDB instance — starting full database backup: ${backup_file}"
      mkdir -p /home

      if command -v ionice >/dev/null 2>&1; then
        ionice -c2 -n7 nice -n 19 "${mysqldump_cmd_base[@]}" | gzip -c > "${backup_file}"
      else
        nice -n 19 "${mysqldump_cmd_base[@]}" | gzip -c > "${backup_file}"
      fi

      if [ -s "${backup_file}" ]; then
        echo "[backup] Backup completed successfully: ${backup_file}"
        backup_done=1
      else
        echo "[backup][WARN] Backup file is empty — possible backup failure: ${backup_file}"
      fi
    else
      echo "[backup][WARN] Unable to connect to MariaDB — skipping backup (no root credentials or service unavailable)."
    fi

    echo "Purging MariaDB (if any)..."
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    systemctl disable mariadb 2>/dev/null || true
    systemctl disable mysql 2>/dev/null || true
    rm -f /etc/systemd/system/mariadb.service /etc/systemd/system/mysql.service
    systemctl daemon-reload || true

    rm -rf /usr/local/mariadb /usr/local/mroonga /etc/my.cnf /etc/mysql /home/mariadb \
           /var/lib/mysql /var/log/mysql \
           /usr/bin/mysql* /usr/bin/mysqld* /root/mariadb-* /root/mroonga* /usr/local/src/mariadb-*

    apt purge -y 'mariadb*' 'mysql-*' 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    if [ "$backup_done" -eq 1 ]; then
      echo "[done] MariaDB has been purged. Backup saved at: ${backup_file}"
    else
      echo "[done] MariaDB has been purged (no backup created or backup failed)."
    fi
  fi
}



remove(){
  purge_nginx
  purge_php
  purge_mariadb
  echo "nginx,php,mariadbhas been fully removed"
  exit 0

}
renginx(){
  purge_nginx
  echo "nginxhas been removed"
  exit 0

}

rephp(){
  purge_php
  echo "phphas been removed"
  exit 0

}

remariadb(){
  purge_mariadb
  echo "mariadbhas been removed"
  exit 0

}



KERNEL_TUNE_ONLY=0




sshkey() {

  echo
  echo "====================================================================="
  echo "⚠️  Strong Reminder: Before you confirm that the PRIVATE KEY has been saved on your local computer,"
  echo "⚠️  DO NOT disconnect this SSH session, otherwise you will lose access to the server!"
  echo "====================================================================="
  echo
  read -rp "Continue and enable root key-only login? (type yes to confirm): " ans
  if [[ "${ans,,}" != "yes" ]]; then
    echo "[safe] Operation canceled. No changes made."
    return 0
  fi


  local SSHD_BIN=""
  if SSHD_BIN="$(command -v sshd 2>/dev/null || true)"; [[ -z "${SSHD_BIN}" ]]; then
    [[ -x /usr/sbin/sshd ]] && SSHD_BIN="/usr/sbin/sshd"
  fi
  [[ -z "${SSHD_BIN}" && -x /sbin/sshd ]] && SSHD_BIN="/sbin/sshd"
  if [[ -z "${SSHD_BIN}" ]]; then
    echo "[safe][ERROR] sshd executable not found. Please install openssh-server first."
    return 1
  fi

  local SSH_USER="root"
  local SSH_HOME="/root"
  local SSH_DIR="${SSH_HOME}/.ssh"
  local KEY_NAME="wnmp_ed25519"
  local PRIV_KEY="${SSH_DIR}/${KEY_NAME}"
  local PUB_KEY="${PRIV_KEY}.pub"
  local AUTH_KEYS="${SSH_DIR}/authorized_keys"
  local NOW="$(date +%Y%m%d-%H%M%S)"
  local HOSTN="$(hostname -f 2>/dev/null || hostname)"
  local COMMENT="${SSH_USER}@${HOSTN}-${NOW}"

  local SSHD_MAIN="/etc/ssh/sshd_config"
  local SSHD_BAK="${SSHD_MAIN}.bak-${NOW}"
  local OVR_DIR="/etc/ssh/sshd_config.d"
  local OVR_FILE="${OVR_DIR}/zzz-root-keys-only.conf"
  local OVR_BACKUP_DIR="/etc/ssh/sshd_config.d.bak-${NOW}"

  echo "[safe] Configuring root user for [key-only login]..."

  if grep -Eq '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+[[:space:]]+[^#]+' "$SSHD_MAIN"; then
    cp -a "$SSHD_MAIN" "${SSHD_MAIN}.prelint-${NOW}"
    sed -i -E 's/^([[:space:]]*ClientAliveInterval)[[:space:]]+[0-9]+.*/\1 120/' "$SSHD_MAIN"
    echo "[safe] Fixed malformed tail comment: ClientAliveInterval line normalized to 'ClientAliveInterval 120'"
  fi


  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  chown -R root:root "${SSH_DIR}"


  if ! ls /etc/ssh/ssh_host_*key >/dev/null 2>&1; then
    echo "[safe] No host keys found, generating (ssh-keygen -A)..."
    ssh-keygen -A
  fi


  local PASSPHRASE_OPT=""
  echo
  read -rp "Add a passphrase to the new key (you’ll need it when logging in)? [y/N]: " setpass
  if [[ "${setpass,,}" =~ ^(y|yes)$ ]]; then
    echo "[safe] Passphrase will be set for the new key..."
    PASSPHRASE_OPT="-N"
  else
    PASSPHRASE_OPT="-N \"\""
  fi


  if [[ -f "${PRIV_KEY}" || -f "${PUB_KEY}" ]]; then
    echo "[safe] Existing root key pair detected, backing up..."
    [[ -f "${PRIV_KEY}" ]] && mv -f "${PRIV_KEY}" "${PRIV_KEY}.bak-${NOW}"
    [[ -f "${PUB_KEY}"  ]] && mv -f "${PUB_KEY}"  "${PUB_KEY}.bak-${NOW}"
  fi

  echo "[safe] Generating ED25519 key pair..."
  if [[ "${PASSPHRASE_OPT}" == "-N" ]]; then
    ssh-keygen -t ed25519 -a 100 -C "${COMMENT}" -f "${PRIV_KEY}"
  else
    ssh-keygen -t ed25519 -a 100 -N "" -C "${COMMENT}" -f "${PRIV_KEY}" >/dev/null
  fi

  chmod 600 "${PRIV_KEY}"
  chmod 644 "${PUB_KEY}"
  chown root:root "${PRIV_KEY}" "${PUB_KEY}"


  touch "${AUTH_KEYS}"
  chmod 600 "${AUTH_KEYS}"
  chown root:root "${AUTH_KEYS}"


local NEW_KEY_TYPE NEW_KEY_B64 NEW_KEY_LINE
NEW_KEY_TYPE=$(awk '{print $1}' "${PUB_KEY}" | tr -d '
' || true)
NEW_KEY_B64=$(awk '{print $2}' "${PUB_KEY}" | tr -d '
' || true)
NEW_KEY_LINE="${NEW_KEY_TYPE} ${NEW_KEY_B64} ${COMMENT}"

if [[ -z "${NEW_KEY_TYPE}" || -z "${NEW_KEY_B64}" ]]; then
  echo "[safe][ERROR] Unable to parse generated public key. Please check ${PUB_KEY}."
  return 1
fi

if [[ -f "${AUTH_KEYS}" ]]; then
  cp -a "${AUTH_KEYS}" "${AUTH_KEYS}.bak-${NOW}"
  echo "[safe] Original authorized_keys backed up as ${AUTH_KEYS}.bak-${NOW}"
else
  touch "${AUTH_KEYS}"
fi
chmod 600 "${AUTH_KEYS}"
chown root:root "${AUTH_KEYS}"


printf '%s
' "${NEW_KEY_LINE}" > "${AUTH_KEYS}.tmp"

chmod 600 "${AUTH_KEYS}.tmp"
chown root:root "${AUTH_KEYS}.tmp"
mv -f "${AUTH_KEYS}.tmp" "${AUTH_KEYS}"

echo "[safe] Authorized key file updated: only the newly generated key retained (${AUTH_KEYS}). Old keys backed up to ${AUTH_KEYS}.bak-${NOW}."

find "${SSH_DIR}" -maxdepth 1 -type f \( -name "${KEY_NAME}.bak-*" -o -name "${KEY_NAME}.pub.bak-*" -o -name "${KEY_NAME}.pub.bak-*" \) -print -exec rm -f {} \; || true

find "${SSH_DIR}" -maxdepth 1 -type f -name "${KEY_NAME}.*.bak-*" -print -exec rm -f {} \; || true

echo "[safe] Removed historical private/public key backups (if any)."

chmod 700 "${SSH_DIR}"
chmod 600 "${PRIV_KEY}"
chmod 644 "${PUB_KEY}"
chown root:root "${PRIV_KEY}" "${PUB_KEY}"


  cp -a "${SSHD_MAIN}" "${SSHD_BAK}"
  echo "[safe] Main config backed up: ${SSHD_BAK}"

  mkdir -p "${OVR_DIR}"
  if [ "$(find "${OVR_DIR}" -type f | wc -l)" -gt 0 ]; then
    mkdir -p "${OVR_BACKUP_DIR}"
    find "${OVR_DIR}" -maxdepth 1 -type f -print -exec mv -f {} "${OVR_BACKUP_DIR}/" \;
    echo "[safe] Backed up and cleared /etc/ssh/sshd_config.d -> ${OVR_BACKUP_DIR}"
  fi


  cat >"${OVR_FILE}" <<'EOF'
# --- Managed by wnmp.sh safe(): only root via public key ---
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
AllowUsers root
# AuthenticationMethods publickey
# -----------------------------------------------------------
EOF


  grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$SSHD_MAIN" || echo "PasswordAuthentication no" >> "$SSHD_MAIN"
  grep -Eq '^[[:space:]]*KbdInteractiveAuthentication[[:space:]]+' "$SSHD_MAIN" || echo "KbdInteractiveAuthentication no" >> "$SSHD_MAIN"
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_MAIN" || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSHD_MAIN"


  echo "[safe] Checking sshd configuration syntax (${SSHD_BIN} -t)..."
  if ! err="$("${SSHD_BIN}" -t 2>&1)"; then
    echo "[safe][ERROR] sshd -t failed:"; echo "$err"
    echo "[safe] Rolling back..."
    rm -f "${OVR_FILE}" || true
    mv -f "${SSHD_BAK}" "${SSHD_MAIN}"
    if [ -d "${OVR_BACKUP_DIR}" ]; then
      find "${OVR_BACKUP_DIR}" -type f -exec mv -f {} "${OVR_DIR}/" \;
      rmdir "${OVR_BACKUP_DIR}" 2>/dev/null || true
    fi
    return 1
  fi


  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload ssh 2>/dev/null || systemctl restart ssh || systemctl restart sshd
  elif command -v service >/dev/null 2>&1; then
    service ssh reload 2>/dev/null || service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  else
    pkill -x sshd >/dev/null 2>&1 || true
    "${SSHD_BIN}" -D >/dev/null 2>&1 &
  fi


  echo
  echo "[safe] Public key fingerprint (SHA256):"
  ssh-keygen -lf "${PUB_KEY}" -E sha256 | awk '{print " - "$0}'
  echo
  echo "====================================================================="
  echo "✅ Root key-only login enabled successfully."
  echo
  echo "🔐 IMPORTANT: DO NOT copy/paste the private key content."
  echo "🔐 Private keys must be transferred as FILES to avoid corruption."
  echo
  echo "➡️  Download the private key using SCP (recommended):"
  echo
  echo "   scp -P <SSH_PORT> root@<SERVER_IP>:/root/.ssh/${KEY_NAME} ~/.ssh/${KEY_NAME}"
  echo
  echo "   Then set permissions:"
  echo "   chmod 600 ~/.ssh/${KEY_NAME}"
  echo
  echo "➡️  Or download via SFTP (WinSCP / FileZilla / Xshell File Transfer)."
  echo
  echo "====================================================================="
  echo

  
  local SERVER_IP
  SERVER_IP="$(ip -o -4 addr show | awk '!/ lo / && /inet /{gsub(/\/.*/,"",$4); print $4; exit}')"
  echo "[safe] Test command: ssh -i ~/.ssh/${KEY_NAME} root@<SERVER>"
  [[ -n "${SERVER_IP:-}" ]] && echo "      Current server IP: ${SERVER_IP}"
  echo
  echo "[safe] Enabled: root login via key only."
  echo "[safe] To revert: mv -f ${SSHD_BAK} ${SSHD_MAIN} && systemctl restart ssh"

  
  echo
  echo "⚠️  Advanced option (NOT recommended)"
  echo "⚠️  Only use this if SCP / SFTP cannot be used"
  echo "⚠️  Copying private keys manually is very error-prone"
  echo

  read -rp "Do you still want to export the private key as String? (advanced users only) [y/N]: " export_string </dev/tty

  if [[ "${export_string,,}" =~ ^(y|yes)$ ]]; then
    echo
    cat "${PRIV_KEY}"
    echo
    echo "⚠️  Note: Do NOT use editors like Windows Notepad that may alter line endings or encoding"
  fi




}






echo "[setup] args: $*"

for arg in "$@"; do
   case "${arg}" in
     tool) KERNEL_TUNE_ONLY=1 ;;
     vhost) vhost; exit 0 ;;
     -h|--help|help) usage; exit 0 ;;
     restart) restart; exit 0 ;;
     status) status; exit 0 ;;
     webdav) webdav; exit 0 ;;
     sshkey) sshkey; exit 0 ;;
     remove) remove; exit 0 ;;
     renginx) renginx; exit 0 ;;
     rephp) rephp; exit 0 ;;
     remariadb) remariadb; exit 0 ;;
     wslinit) wslinit; exit 0 ;;
     fixsshd) fixsshd; exit 0 ;;
     "") ;;
     *) echo "[setup] Unknown parameter: ${arg}"; usage; exit 1 ;;
   esac
 done

if [[ "$IS_LAN" -eq 1 ]]; then
red "[env] Detected a LAN environment, certificate issuance will be skipped."
read -rp "Do you want to force certificate issuance? [y/N] " ans
ans="${ans:-N}"
if [[ "$ans" =~ [Yy]$ ]]; then
  green "[env] Forced certificate issuance enabled."
  IS_LAN=0
else
  red "[env] Certificate issuance remains skipped."
fi
else
green "[env] Public network detected, certificate issuance is available."
fi


MYSQL_PASS='needpasswd'


CORES=$(nproc)
MAX=$(( $(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}') / 1 ))
JOBS=$(( CORES < MAX ? CORES : MAX ))
(( JOBS < 1 )) && JOBS=1


export CFLAGS="-O2 -pipe -fPIC -DNDEBUG -g0"
export CXXFLAGS="-O2 -pipe -fPIC -DNDEBUG -g0"
export LDFLAGS="-Wl,--as-needed -Wl,--no-keep-memory"


log() { echo "[setup] $*"; }
trap 's=$?; echo "[setup][ERROR] exit $s at line $LINENO: ${BASH_COMMAND}"; exit $s' ERR

GREEN='\e[32m'; RED='\e[31m'; NC='\e[0m'


if [ "$(id -u)" -ne 0 ]; then
  echo "Error: you must be root to run this script."
  exit 1
fi
 is_wsl=0
if grep -qi "microsoft" /proc/version 2>/dev/null; then
  is_wsl=1
fi

wnmp_limits_tune() {
  local NOFILE="${1:-1048576}"
  local NPROC="${2:-65535}"
  local LIMITS_FILE="/etc/security/limits.conf"
  install -d "$(dirname "$LIMITS_FILE")" 2>/dev/null || true
  [ -f "$LIMITS_FILE" ] || : > "$LIMITS_FILE"

  sed -i -E \
    -e '/^[[:space:]]*\*[[:space:]]+(soft|hard)[[:space:]]+nofile[[:space:]]+/d' \
    -e '/^[[:space:]]*\*[[:space:]]+(soft|hard)[[:space:]]+nproc[[:space:]]+/d' \
    "$LIMITS_FILE" 2>/dev/null || true

  cat >> "$LIMITS_FILE" <<EOF

* soft nofile ${NOFILE}
* hard nofile ${NOFILE}

* soft nproc ${NPROC}
* hard nproc ${NPROC}
EOF

  echo "[limits] ${LIMITS_FILE} updated: nofile=${NOFILE}, nproc=${NPROC}"

  local SYSTEMD_CONF="/etc/systemd/system.conf"
  install -d "$(dirname "$SYSTEMD_CONF")" 2>/dev/null || true
  [ -f "$SYSTEMD_CONF" ] || : > "$SYSTEMD_CONF"

  sed -i -E \
    -e '/^[[:space:]]*DefaultLimitNOFILE[[:space:]]*=/d' \
    -e '/^[[:space:]]*DefaultLimitNPROC[[:space:]]*=/d' \
    "$SYSTEMD_CONF" 2>/dev/null || true

  cat >> "$SYSTEMD_CONF" <<EOF

DefaultLimitNOFILE=${NOFILE}
DefaultLimitNPROC=${NPROC}
EOF

  echo "[systemd] ${SYSTEMD_CONF} appended: DefaultLimitNOFILE=${NOFILE}, DefaultLimitNPROC=${NPROC}"

  local SYSTEMD_USER_CONF="/etc/systemd/user.conf"
  install -d "$(dirname "$SYSTEMD_USER_CONF")" 2>/dev/null || true
  [ -f "$SYSTEMD_USER_CONF" ] || : > "$SYSTEMD_USER_CONF"

  sed -i -E \
    -e '/^[[:space:]]*DefaultLimitNOFILE[[:space:]]*=/d' \
    -e '/^[[:space:]]*DefaultLimitNPROC[[:space:]]*=/d' \
    "$SYSTEMD_USER_CONF" 2>/dev/null || true

  cat >> "$SYSTEMD_USER_CONF" <<EOF

DefaultLimitNOFILE=${NOFILE}
DefaultLimitNPROC=${NPROC}
EOF

  echo "[systemd] ${SYSTEMD_USER_CONF} appended: DefaultLimitNOFILE=${NOFILE}, DefaultLimitNPROC=${NPROC}"
  systemctl daemon-reload >/dev/null 2>&1 || true
}

wnmp_kernel_tune() {


  local SYSCTL_FILE="${1:-/etc/sysctl.d/99-wnmp.conf}"
  local SECTION_TAG_BEGIN="# ==== wnmp TUNING BEGIN ===="
  local SECTION_TAG_END="# ==== wnmp TUNING END ===="


  install -d "$(dirname "$SYSCTL_FILE")" 2>/dev/null || true
  if [ ! -f "$SYSCTL_FILE" ]; then
    echo "[sysctl] create ${SYSCTL_FILE}"
    printf '# created by wnmp setup\n' > "$SYSCTL_FILE"
  fi


  awk -v b="$SECTION_TAG_BEGIN" -v e="$SECTION_TAG_END" '
    BEGIN{inblk=0}
    $0==b {inblk=1; next}
    $0==e {inblk=0; next}
    !inblk {print}
  ' "$SYSCTL_FILE" > "${SYSCTL_FILE}.tmp" && mv "${SYSCTL_FILE}.tmp" "$SYSCTL_FILE"

  {
    echo ""
    echo "$SECTION_TAG_BEGIN"
    cat <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 1000000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_syncookies = 1

EOF
    echo "$SECTION_TAG_END"
  } >> "$SYSCTL_FILE"

  echo "[sysctl] Optimized block to: $SYSCTL_FILE"


  if [ -d /sys/kernel/mm/transparent_hugepage ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled  2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag    2>/dev/null || true
    cat >/etc/systemd/system/disable-thp.service <<'UNIT'
[Unit]
Description=Disable Transparent Huge Pages
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable disable-thp.service >/dev/null 2>&1 || true
    echo "[thp] THP has been disabled and set to take effect at startup." 
  fi


  modprobe tcp_bbr 2>/dev/null || true


  echo "[sysctl] Reloading kernel parameters..."
  if [[ "$SYSCTL_FILE" == */sysctl.conf ]]; then
    sysctl -p || true
  else
    SYSTEMD_LOG_LEVEL=info sysctl --system || true
  fi

  wnmp_limits_tune 1048576 65535


  echo -e "\033[32mKernel / network tuning completed (including BBR/fq, THP disabled, and limits configuration)\033[0m"
  read -rp "A reboot is recommended to ensure all settings take effect (WSL requires restarting the Windows 11 host). Reboot now? [Y/n] " yn
  [ -z "${yn:-}" ] && yn="y"
  if [[ "$yn" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Rebooting..."
    reboot
  fi
  
  
}



if [ "$KERNEL_TUNE_ONLY" -eq 1 ]; then
  echo "[setup] kernel-only mode ON"
  
  wnmp_kernel_tune
 
  echo -e "${GREEN}Kernel/Network tuning only is complete${NC}"
  exit 0
fi



ensure_group() {
  local g="$1"
  if getent group "$g" >/dev/null 2>&1; then
    log "group '$g' already exists"
  else
    groupadd "$g"
    log "group '$g' created"
  fi
}
ensure_user() {
  local u="$1" g="$2"
  if id -u "$u" >/dev/null 2>&1; then
    log "user '$u' already exists"
  else
    useradd -s /sbin/nologin -M -g "$g" "$u"
    log "user '$u' created (group '$g')"
  fi
}


install -m 0644 /dev/stdin /etc/profile.d/wnmp-path.sh <<'EOF'
# WNMP: global PATH for login/interactive shells
export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:${PATH}"
EOF

if ! grep -q 'wnmp-path.sh' /etc/bash.bashrc 2>/dev/null; then
  printf '\n# WNMP PATH for interactive shells\n[ -f /etc/profile.d/wnmp-path.sh ] && . /etc/profile.d/wnmp-path.sh\n' >> /etc/bash.bashrc
fi

export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:${PATH}"
hash -r

echo -e "${GREEN}PATH has been written to /etc/profile.d/wnmp-path.sh and injected into /etc/bash.bashrc; the current session is now active.${NC}"
echo -e "${GREEN}PHP path: $(command -v php || echo 'Not found')${NC}"



PHP="/usr/local/php/bin/php"
PHPIZE="/usr/local/php/bin/phpize"
PHPCONFIG="/usr/local/php/bin/php-config"



if [ -f /root/.pearrc ] || [ -f /usr/local/php/etc/pear.conf ]; then
  echo -e "${RED}Old PEAR config found; removing to avoid PEAR/PECL errors...${NC}"
  rm -f /root/.pearrc /usr/local/php/etc/pear.conf
fi




if swapon --noheadings --show=NAME | grep -q .; then
  log "Existing swap detected. Disabling all..."
  swapoff -a || true
  if [ -f /swapfile ]; then
    rm -f /swapfile
    log "Old /swapfile removed."
  fi
fi
log "Creating /swapfile (1G)..."
if command -v fallocate >/dev/null 2>&1; then
  fallocate -l 1G /swapfile || {
    log "fallocate failed, fallback to dd..."
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
  }
else
  dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
fi
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
log "Swap activated."
sed -i '/\/swapfile[[:space:]]\+none[[:space:]]\+swap/d' /etc/fstab
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=60' > /etc/sysctl.d/99-swap.conf
sysctl -p /etc/sysctl.d/99-swap.conf || true
log "Current swap status:"; swapon --show || true; free -h || true


echo "Please select PHP version:" 
php_version='0'
select phpselcect in "Do not install PHP" "php8.2" "php8.3" "php8.4" "php8.5" ; do
  case $phpselcect in
    "Do not install PHP") php_version='0'; break ;;
    "php8.2") php_version='8.2.29'; break ;;
    "php8.3") php_version='8.3.28'; break ;;
    "php8.4") php_version='8.4.15'; break ;;
    "php8.5") php_version='8.5.0'; break ;;
    *) echo "Invalid option $REPLY" ;; 
  esac
done

echo "Select MariaDB version:"
mariadbselcect=''
mariadb_version='0'
select mariadbselcect in "Do not install MariaDB" "1GB Memory 10.6" "2GB The above memory 10.11" "4GB The above memory 11.8.5"; do
  case $mariadbselcect in
    "Do not install MariaDB") mariadb_version='0'; break ;;
    "1GB Memory 10.6") mariadb_version='10.6.24'; break ;;
    "2GB The above memory 10.11") mariadb_version='10.11.15'; break ;;
    "4GB The above memory 11.8.5") mariadb_version='11.8.5'; break ;;
    *) echo "Invalid option $REPLY";; 
  esac
done
if [ "$mariadb_version" != "0" ]; then
  read -p "Enter MySQL root password [Default: needpasswd]: " MYSQL_PASS 
  MYSQL_PASS=${MYSQL_PASS:-needpasswd}
fi
read -rp "Install NGINX?(y/n): " choosenginx


apt --fix-broken install -y
apt autoremove -y
apt update
apt install -y libc-ares-dev apache2-utils git liblzma-dev libedit-dev libncurses5-dev libnuma-dev libaio-dev libsnappy-dev libicu-dev liblz4-dev screen build-essential liburing-dev liburing2 \
  libzstd-dev wget curl m4 autoconf re2c pkg-config libxml2-dev libcurl4-openssl-dev \
  libbz2-dev openssl libssl-dev libtidy-dev libxslt1-dev libsqlite3-dev zlib1g-dev \
  libpng-dev libjpeg-dev libwebp-dev libonig-dev libzip-dev libpcre2-8-0 libpcre2-dev \
  cmake bison libncurses-dev libfreetype-dev unzip


ensure_group www
ensure_user  www www


if [ "$php_version" != "0" ]; then
  cd /root
  purge_php
  php_dir="php-$php_version"
  rm -rf "$php_dir"
  if [ ! -d "$php_dir" ]; then
    php_url="https://www.php.net/distributions/php-$php_version.tar.gz"
    wget -c "$php_url"
    tar zxvf "php-$php_version.tar.gz"
  else
    log "php-$php_version exists"
  fi

  cd "$php_dir"
  make distclean || true


PREFIX="/usr/local/php"
PHP_ETC="${PREFIX}/etc"
PHP_CONF_D="${PREFIX}/conf.d"
FPM_USER="www"
FPM_GROUP="www"
CONFIGURE_OPTS=(
  "--prefix=${PREFIX}"
  "--with-config-file-path=${PHP_ETC}"
  "--with-config-file-scan-dir=${PHP_CONF_D}"
  "--with-pear"
  "--enable-phar"
  "--disable-zts" 
  "--disable-rpath"
  "--disable-fileinfo"    
  "--enable-exif"
  "--enable-intl"
  "--enable-fpm"
  "--with-fpm-user=${FPM_USER}"
  "--with-fpm-group=${FPM_GROUP}"
  "--enable-mysqlnd"
  "--with-mysqli=mysqlnd"
  "--with-pdo-mysql=mysqlnd"
  "--with-jpeg"
  "--with-freetype"
  "--with-webp"
  "--enable-gd"
  "--with-zlib"
  "--enable-xml"
  "--enable-pcntl"
  "--enable-bcmath"
  "--with-curl"
  "--enable-mbregex"
  "--enable-mbstring"
  "--with-openssl"
  "--with-mhash"
  "--enable-sockets"
  "--with-zip"
)

if [[  "$php_version" =~ ^8\.2\. ]]; then
 CONFIGURE_OPTS+=("--enable-opcache")
fi

./configure "${CONFIGURE_OPTS[@]}"

  make -j${JOBS}
  make install

  find /usr/local/php -type f -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
  strip /usr/local/php/bin/php 2>/dev/null || true
  strip /usr/local/php/sbin/php-fpm 2>/dev/null || true

  cat <<'EOF' > /etc/systemd/system/php-fpm.service
[Unit]
Description=The PHP FastCGI Process Manager
After=network.target

[Service]
Type=simple
PIDFile=/usr/local/php/var/run/php-fpm.pid
ExecStart=/usr/local/php/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload

  cat <<'EOF' > /usr/local/php/etc/php-fpm.conf
[global]
pid = /usr/local/php/var/run/php-fpm.pid
error_log = /usr/local/php/var/log/php-fpm.log
log_level = notice

[www]
listen = /tmp/php-cgi.sock
listen.backlog = -1
listen.allowed_clients = 127.0.0.1
listen.owner = www
listen.group = www
listen.mode = 0666
user = www
group = www
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 1024
pm.process_idle_timeout = 10s
request_terminate_timeout = 0
request_slowlog_timeout = 5s
slowlog = /usr/local/php/var/log/slow.log
EOF

php_version="${php_version:-$("$PHP" -r 'echo PHP_VERSION;')}"

if [[ "$php_version" =~ ^8\.5\. ]]; then
  cat <<'EOF' > /usr/local/php/etc/php.ini
extension=swoole.so
extension=inotify.so
extension=redis.so
extension=apcu.so
[PHP]
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1
zend.enable_gc = On
zend.exception_ignore_args = On
zend.exception_string_param_max_len = 0
expose_php = On
max_execution_time = 300
memory_limit = 1G
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
variables_order = "GPCS"
request_order = "GP"
file_uploads = On
upload_max_filesize = 10G
post_max_size = 10G
max_file_uploads = 100
max_input_time = 0
upload_tmp_dir = /data/php_upload_tmp
allow_url_fopen = Off
allow_url_include = Off
default_socket_timeout = 60

[Pdo_mysql]
pdo_mysql.default_socket=/tmp/mariadb.sock

[MySQLi]
mysqli.default_socket = /tmp/mariadb.sock

[Session]
session.save_handler = files
session.save_path = "/tmp"
session.use_strict_mode = 1
session.use_only_cookies = 1
session.cookie_httponly = 1
session.cookie_secure = 1
session.cookie_samesite = Lax
session.gc_maxlifetime = 1440
session.sid_length = 48
session.sid_bits_per_character = 6

[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=100000
opcache.validate_timestamps=1
opcache.revalidate_freq=1
opcache.jit=tracing
opcache.jit_buffer_size=64M
opcache.save_comments=1
opcache.enable_file_override=0

[apcu]
apc.enabled=1
apc.shm_size=128M
apc.entries_hint=262144
apc.ttl=0
apc.gc_ttl=3600
apc.enable_cli=1

EOF

else
    cat <<'EOF' > /usr/local/php/etc/php.ini
extension=swoole.so
extension=inotify.so
extension=redis.so
extension=apcu.so
zend_extension=opcache
[PHP]
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1
zend.enable_gc = On
zend.exception_ignore_args = On
zend.exception_string_param_max_len = 0
expose_php = On
max_execution_time = 300
memory_limit = 1G
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
variables_order = "GPCS"
request_order = "GP"
file_uploads = On
upload_max_filesize = 10G
post_max_size = 10G
max_file_uploads = 100
max_input_time = 0
upload_tmp_dir = /data/php_upload_tmp
allow_url_fopen = Off
allow_url_include = Off
default_socket_timeout = 60

[Pdo_mysql]
pdo_mysql.default_socket=/tmp/mariadb.sock

[MySQLi]
mysqli.default_socket = /tmp/mariadb.sock

[Session]
session.save_handler = files
session.save_path = "/tmp"
session.use_strict_mode = 1
session.use_only_cookies = 1
session.cookie_httponly = 1
session.cookie_secure = 1
session.cookie_samesite = Lax
session.gc_maxlifetime = 1440
session.sid_length = 48
session.sid_bits_per_character = 6

[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=100000
opcache.validate_timestamps=1
opcache.revalidate_freq=1
opcache.jit=tracing
opcache.jit_buffer_size=64M
opcache.save_comments=1
opcache.enable_file_override=0

[apcu]
apc.enabled=1
apc.shm_size=128M
apc.entries_hint=262144
apc.ttl=0
apc.gc_ttl=3600
apc.enable_cli=1
EOF
fi


  systemctl enable php-fpm
  systemctl start php-fpm
  cd /root
  curl -fL --output /tmp/pie.phar https://github.com/php/pie/releases/latest/download/pie.phar \
  && mv /tmp/pie.phar /usr/local/php/bin/pie \
  && chmod +x /usr/local/php/bin/pie

pecl channel-update pecl.php.net

if [[ "$php_version" =~ ^8\.5\. ]]; then
  wget -c https://github.com/swoole/swoole-src/archive/master.tar.gz -O swoole.tar.gz
else
  wget -c https://github.com/swoole/swoole-src/archive/refs/tags/v6.1.4.tar.gz -O swoole.tar.gz
fi
  
  tar zxvf ./swoole.tar.gz && \
  mv swoole-src* swoole-src && \
  cd swoole-src && \
  phpize && \
  ./configure --with-php-config=/usr/local/php/bin/php-config \
  --enable-openssl  --enable-mysqlnd --enable-swoole-curl --enable-cares --enable-iouring --enable-zstd && \
  make && make install

  if [[ -x /usr/local/php/bin/pie ]]; then
    /usr/local/php/bin/pie install phpredis/phpredis || printf "\n" | pecl install redis
  else
    printf "\n" | pecl install redis
  fi
  if [[ -x /usr/local/php/bin/pie ]]; then
    /usr/local/php/bin/pie install arnaud-lb/inotify || printf "\n" | pecl install inotify
  else
    printf "\n" | pecl install inotify
  fi
  if [[ -x /usr/local/php/bin/pie ]]; then
    /usr/local/php/bin/pie install apcu/apcu || printf "\n" | pecl install apcu
  else
    printf "\n" | pecl install apcu
  fi

else
  echo 'Do not install PHP'
fi


case "$choosenginx" in
  y|Y|yes|YES|Yes)
    purge_nginx
    cd /root
    apt-get install -y cron curl socat tar
    systemctl enable --now cron

    curl https://get.acme.sh | sh -s email=1@gmail.com
    bash /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
    if [[ "$IS_LAN" -eq 0 ]]; then
      echo "$PUBLIC_IP"
      acme.sh --issue --server letsencrypt -d "$PUBLIC_IP" --certificate-profile shortlived  --standalone --force
    fi

    mkdir -p /home/wwwroot/default
    mkdir -p /home/wwwlogs
    mkdir -p /home/passwd
    htpasswd -bc /home/passwd/.default wnmp ${MYSQL_PASS}
    chown -R www:www /home/passwd
    chown -R www:www /home/wwwroot
    chown -R www:www /home/wwwlogs

    

    
    rm -rf nginx-1.28.0
    wget -c https://nginx.org/download/nginx-1.28.0.tar.gz
    tar zxvf nginx-1.28.0.tar.gz
    cd nginx-1.28.0
    git --version >/dev/null || { log "git missing"; exit 1; }
    git clone --depth=1 https://github.com/arut/nginx-dav-ext-module.git
    make clean || true

    ./configure \
      --prefix=/usr/local/nginx \
      --user=www \
      --group=www \
      --sbin-path=/usr/local/nginx/sbin/nginx \
      --conf-path=/usr/local/nginx/nginx.conf \
      --error-log-path=/usr/local/nginx/error.log \
      --http-log-path=/usr/local/nginx/access.log \
      --pid-path=/usr/local/nginx/nginx.pid \
      --lock-path=/usr/local/nginx/nginx.lock \
      --http-client-body-temp-path=/usr/local/nginx/client_temp \
      --http-proxy-temp-path=/usr/local/nginx/proxy_temp \
      --http-fastcgi-temp-path=/usr/local/nginx/fastcgi_temp \
      --http-uwsgi-temp-path=/usr/local/nginx/uwsgi_temp \
      --http-scgi-temp-path=/usr/local/nginx/scgi_temp \
      --with-file-aio \
      --with-threads \
      --with-http_addition_module \
      --with-http_auth_request_module \
      --with-http_dav_module \
      --with-http_gunzip_module \
      --with-http_gzip_static_module \
      --with-http_realip_module \
      --with-http_secure_link_module \
      --with-http_slice_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      --with-http_sub_module \
      --with-http_v2_module \
      --with-stream \
      --with-stream_realip_module \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-pcre-jit \
      --with-http_mp4_module \
      --with-cc-opt="-O2 -pipe -fstack-protector-strong -fPIC -Wformat -Werror=format-security" \
      --with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed" \
      --add-module=./nginx-dav-ext-module

    make -j${JOBS}
    make install
    strip /usr/local/nginx/sbin/nginx || true

    cat <<'EOF' > /etc/systemd/system/nginx.service
[Unit]
Description=nginx
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=false
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF

mkdir -p /usr/local/nginx/rewrite /usr/local/nginx/ssl/default /usr/local/nginx/vhost

cat <<'EOF' >  /usr/local/nginx/download.conf
types { }
default_type application/octet-stream;
autoindex on;            
autoindex_exact_size off;    
autoindex_localtime on;      
charset utf-8; 
sendfile on;
aio on;
directio 4m;
output_buffers 1 512k;           
location ~* \.html?$ {
    default_type application/octet-stream;
    add_header Content-Disposition "attachment" always;
    add_header X-Content-Type-Options "nosniff" always;
    try_files $uri 404;
}

location ~* \.php?$ {
    default_type application/octet-stream;
    add_header Content-Disposition "attachment" always;
    add_header X-Content-Type-Options "nosniff" always;
    try_files /404.html =404;
}
EOF

cat <<'EOF' >  /usr/local/nginx/html/403.html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, viewport-fit=cover">
<title>403 Forbidden</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f7f7f7;
    --text: #222;
    --accent: #e74c3c;
    --shadow: rgba(0,0,0,0.1);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #111;
      --text: #eee;
      --shadow: rgba(255,255,255,0.05);
    }
  }
  body {
    margin: 0;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    padding: 0 15px;
  }
  .box {
    text-align: center;
    padding: 3rem 2rem;
    border-radius: 1rem;
    box-shadow: 0 0 20px var(--shadow);
    animation: fadeIn 0.6s ease;
  }
  h1 {
    font-size: 3rem;
    margin: 0.5rem 0;
    color: var(--accent);
  }
  p {
    font-size: 1.1rem;
    color: var(--text);
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>
</head>
<body>
  <div class="box">
    <h1>403</h1>
    <p>Sorry, you don't have permission to access this page.</p>
    <p style="font-size:0.9rem;opacity:0.7;">nginx</p>
    <p style="font-size:0.9rem;opacity:0.7;">This server was built using the one-click package from wnmp.org.</p>
  </div>
</body>
</html>

EOF

cat <<'EOF' >  /usr/local/nginx/html/404.html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, viewport-fit=cover">
<title>404 Not Found</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f7f7f7;
    --text: #222;
    --accent: #e74c3c;
    --shadow: rgba(0,0,0,0.1);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #111;
      --text: #eee;
      --shadow: rgba(255,255,255,0.05);
    }
  }
  body {
    margin: 0;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    padding: 0 15px;
  }
  .box {
    text-align: center;
    padding: 3rem 2rem;
    border-radius: 1rem;
    box-shadow: 0 0 20px var(--shadow);
    animation: fadeIn 0.6s ease;
  }
  h1 {
    font-size: 3rem;
    margin: 0.5rem 0;
    color: var(--accent);
  }
  p {
    font-size: 1.1rem;
    color: var(--text);
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>
</head>
<body>
  <div class="box">
    <h1>404</h1>
    <p>The requested resource could not be found on this server.</p>
    <p style="font-size:0.9rem;opacity:0.7;">nginx</p>
    <p style="font-size:0.9rem;opacity:0.7;">This server was built using the one-click package from wnmp.org.</p>
  </div>
</body>
</html>

EOF



cat <<'EOF' >  /usr/local/nginx/enable-php.conf
location ~ [^/]\.php(/|$)
{
    try_files $uri =404;
    fastcgi_pass  unix:/tmp/php-cgi.sock;
    fastcgi_index index.php;
    include fastcgi.conf;
}
EOF

cat <<'EOF' >  /usr/local/nginx/fastcgi.conf
fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

fastcgi_param  REDIRECT_STATUS    200;
fastcgi_param PHP_ADMIN_VALUE "open_basedir=$document_root/:/tmp/:/proc/";
EOF

cp /usr/local/nginx/fastcgi.conf /usr/local/nginx/fastcgi_params

if [[ "$IS_LAN" -eq 1 ]]; then
cat <<'EOF' >  /usr/local/nginx/nginx.conf
user  www www;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 1000000; 
pid        /usr/local/nginx/nginx.pid;

error_log  /home/wwwlogs/nginx_error.log crit;

events {
    worker_connections 65535;
    use epoll;   
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    dav_ext_lock_zone zone=webdav_locks:10m;
    aio threads;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout   300s;
    keepalive_requests  100000;

    proxy_request_buffering on;
    
    client_body_temp_path /usr/local/nginx/client_body_temp 1 2;
    client_max_body_size 10g;
    client_body_buffer_size 512k;
    client_header_timeout 300s;
    client_body_timeout   1800s;
    send_timeout          1800s;


    real_ip_recursive on;

    gzip on;
    gzip_min_length 10240;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/plain text/css text/xml text/javascript application/javascript
        application/x-javascript application/xml application/xml+rss
        application/json application/ld+json application/x-font-ttf
        font/opentype application/vnd.ms-fontobject image/svg+xml;

    open_file_cache          max=200000 inactive=20s;
    open_file_cache_valid    30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors   on;

    fastcgi_connect_timeout 10s;
    fastcgi_send_timeout    300s;
    fastcgi_read_timeout    1800s;
    fastcgi_request_buffering off;
    fastcgi_buffer_size     64k;
    fastcgi_buffers         4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;

    server_tokens off;

    upstream lowphp {
        server unix:/tmp/lowphp.sock;
        keepalive 100000;
    }
    

    server {
        listen 80 default_server reuseport;
        server_name _;
        root  /home/wwwroot/default;
        index index.html index.php;

        error_page 403 = @e403;

        location @e403 {
            root html;
            internal;
            types { }
            default_type text/html;
            add_header Content-Type "text/html; charset=utf-8";  
            try_files /403.html =403;
        }

        error_page 502 504 404 = @e404;
        location @e404 {
            root html;
            internal;
            types { }
            default_type text/html;
            add_header Content-Type "text/html; charset=utf-8";
            try_files /404.html =404;
        }

        autoindex_exact_size off;
        autoindex_localtime on;
        include enable-php.conf;

        location /nginx_status { stub_status off; access_log off; }

        location ~* \.(gif|jpg|jpeg|png|bmp|webp|ico|svg)$ {
            expires 30d;
            add_header Cache-Control "public, max-age=2592000, immutable";
            access_log off;
        }

        location ~* \.(js|css)$ {
            expires 12h;
            add_header Cache-Control "public, max-age=43200";
            access_log off;
        }
        location ^~ /.well-known/ { allow all; }
        location ~ /\.(?!well-known) {
            deny all;
        }
        location = /phpmyadmin {
            return 301 /phpmyadmin/;
        }
        location ^~ /phpmyadmin/ {
            include enable-php.conf;
            auth_basic "WebDAV Authentication";
            auth_basic_user_file /home/passwd/.default;
           
        }
        
        access_log off;
    }

   
    include vhost/*.conf;
}

EOF

else
cat <<'EOF' >  /usr/local/nginx/nginx.conf
user  www www;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 1000000; 
pid        /usr/local/nginx/nginx.pid;

error_log  /home/wwwlogs/nginx_error.log crit;

events {
    worker_connections 65535;
    use epoll;   
}

http {

    include       mime.types;
    default_type  application/octet-stream;
    dav_ext_lock_zone zone=webdav_locks:10m;
    aio threads;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout   300s;
    keepalive_requests  100000;

    proxy_request_buffering on;
    
    client_body_temp_path /usr/local/nginx/client_body_temp 1 2;
    client_max_body_size 10g;
    client_body_buffer_size 512k;
    client_header_timeout 300s;
    client_body_timeout   1800s;
    send_timeout          1800s;


   
    real_ip_recursive on;

    gzip on;
    gzip_min_length 10240;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/plain text/css text/xml text/javascript application/javascript
        application/x-javascript application/xml application/xml+rss
        application/json application/ld+json application/x-font-ttf
        font/opentype application/vnd.ms-fontobject image/svg+xml;

    open_file_cache          max=200000 inactive=20s;
    open_file_cache_valid    30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors   on;

    fastcgi_connect_timeout 10s;
    fastcgi_send_timeout    300s;
    fastcgi_read_timeout    1800s;
    fastcgi_request_buffering off;
    fastcgi_buffer_size     64k;
    fastcgi_buffers         4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;

    server_tokens off;

    upstream lowphp {
        server unix:/tmp/lowphp.sock;
        keepalive 100000;
    }
    

    server {
        listen 80 default_server reuseport;
        listen 443 ssl  default_server reuseport;
        http2 on;
        server_name _;
        if ($server_port = 80 ) {
            return 301 https://$host$request_uri;
        }
        root  /home/wwwroot/default;
        index index.html index.php;
        error_page 403 = @e403;
        location @e403 {
            root html;
            internal;
            types { }
            default_type text/html;
            add_header Content-Type "text/html; charset=utf-8";  
            try_files /403.html =403;
        }

        error_page 502 504 404 = @e404;
        location @e404 {
            root html;
            internal;
            types { }
            default_type text/html;
            add_header Content-Type "text/html; charset=utf-8";
            try_files /404.html =404;
        }
        ssl_certificate     /usr/local/nginx/ssl/default/cert.pem;
        ssl_certificate_key /usr/local/nginx/ssl/default/key.pem;
        ssl_trusted_certificate /usr/local/nginx/ssl/default/ca.pem;
        ssl_session_cache   shared:SSL:20m;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5:!RC4:!3DES;
        ssl_prefer_server_ciphers off;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        autoindex_exact_size off;
        autoindex_localtime on;
        include enable-php.conf;
        location /nginx_status { stub_status off; access_log off; }

        location ~* \.(gif|jpg|jpeg|png|bmp|webp|ico|svg)$ {
            expires 30d;
            add_header Cache-Control "public, max-age=2592000, immutable";
            access_log off;
        }

        location ~* \.(js|css)$ {
            expires 12h;
            add_header Cache-Control "public, max-age=43200";
            access_log off;
        }
        location ^~ /.well-known/ { allow all; }
        location ~ /\.(?!well-known) {
            deny all;
        }
        location = /phpmyadmin {
            return 301 /phpmyadmin/;
        }
        location ^~ /phpmyadmin/ {
            include enable-php.conf;
            auth_basic "WebDAV Authentication";
            auth_basic_user_file /home/passwd/.default;
           
        }
        
        access_log off;
    }
 
    include vhost/*.conf;
}
EOF
fi

    if [[ "$IS_LAN" -eq 0 ]]; then  
      acme.sh --install-cert -d "$PUBLIC_IP" --ecc --key-file  /usr/local/nginx/ssl/default/key.pem  --fullchain-file /usr/local/nginx/ssl/default/cert.pem --ca-file  /usr/local/nginx/ssl/default/ca.pem
    fi

    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx
    
    ;;
  n|N|no|NO|No)
    echo "You selected ‘No’, skipping the nginx installation..." 
    ;;
  *)
    echo "Invalid input, default exit..." 
    exit 1
    ;;
esac

if [ "$mariadb_version" != "0" ]; then
  purge_mariadb

  cd /root

  ensure_group mariadb
  ensure_user  mariadb mariadb
  mkdir -p /home/mariadb
  mkdir -p /home/mariadb/binlog
  chown -R mariadb:mariadb /home/mariadb


  rm -rf "mariadb-$mariadb_version"
  wget -c "https://archive.mariadb.org/mariadb-$mariadb_version/source/mariadb-$mariadb_version.tar.gz"
  tar zxvf "mariadb-$mariadb_version.tar.gz"

  cd "mariadb-$mariadb_version"
  mkdir build && cd build

  export LDFLAGS="-Wl,--as-needed -Wl,--no-keep-memory"

  cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/mariadb \
    -DMYSQL_DATADIR=/home/mariadb \
    -DMYSQL_UNIX_ADDR=/tmp/mariadb.sock \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_ARCHIVE_STORAGE_ENGINE=0 \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=0 \
    -DWITH_READLINE=1 \
    -DWITH_SSL=system \
    -DWITH_ZLIB=system \
    -DWITH_LIBWRAP=0 \
    -DDEFAULT_CHARSET=utf8mb4 \
    -DDEFAULT_COLLATION=utf8mb4_general_ci \
    -DPLUGIN_CONNECT=NO \
    -DPLUGIN_ROCKSDB=NO \
    -DPLUGIN_SPIDER=NO \
    -DWITH_GROONGA=OFF \
    -DWITHOUT_GROONGA=ON \
    -DWITH_MROONGA=OFF \
    -DPLUGIN_MROONGA=NO
  make -j${JOBS}
  make install

  cp /usr/local/mariadb/support-files/mysql.server /etc/init.d/mariadb
  chmod 755 /etc/init.d/mariadb

  cat <<'EOF' > /etc/my.cnf
[client]
port        = 3306
socket      = /tmp/mariadb.sock

[mysqld]

server-id=1
log-bin=/home/mariadb/binlog/mysql-bin
binlog_format=row
expire_logs_days=3
innodb_flush_log_at_trx_commit=1
sync_binlog=1

character-set-server = utf8mb4
collation-server     = utf8mb4_general_ci
skip-character-set-client-handshake
init_connect='SET NAMES utf8mb4'
sql-mode = NO_ENGINE_SUBSTITUTION
port        = 3306
socket      = /tmp/mariadb.sock
user        = mariadb
basedir     = /usr/local/mariadb
datadir     = /home/mariadb
log_error   = /home/mariadb/mariadb.err
pid-file    = /home/mariadb/mariadb.pid

skip-name-resolve
performance_schema=OFF
event_scheduler=OFF

max_connections = 300
max_connect_errors = 1000
back_log = 1024
thread_cache_size = 256

wait_timeout = 3600
interactive_timeout = 3600

default_storage_engine = InnoDB
innodb_buffer_pool_size = 1G
innodb_buffer_pool_instances = 2

innodb_file_per_table = 1
innodb_flush_log_at_trx_commit = 2
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_lock_wait_timeout = 60


innodb_flush_method = O_DIRECT
innodb_io_capacity = 1000
innodb_io_capacity_max = 2000
innodb_read_io_threads = 8
innodb_write_io_threads = 8

table_open_cache = 10000
open_files_limit = 65535


tmp_table_size = 64M
max_heap_table_size = 64M


slow_query_log = 1
slow_query_log_file = /home/mariadb/slow.log
long_query_time = 0.2
log_queries_not_using_indexes = 0


[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[myisamchk]
key_buffer_size = 128M
sort_buffer_size = 2M
read_buffer = 2M
write_buffer = 2M

[mysqlhotcopy]
interactive-timeout

EOF

  cat <<EOF >  /etc/systemd/system/mariadb.service
[Unit]
Description=MariaDB Server
After=network.target syslog.target

[Service]
Type=forking

ExecStart=/etc/init.d/mariadb start
ExecStop=/etc/init.d/mariadb stop
ExecReload=/etc/init.d/mariadb reload

Restart=no
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

  /usr/local/mariadb/scripts/mysql_install_db --defaults-file=/etc/my.cnf --basedir=/usr/local/mariadb --datadir=/home/mariadb --user=mariadb
  systemctl daemon-reload
  systemctl enable mariadb
  systemctl start mariadb
  cd ..
  set +H
  /usr/local/mariadb/bin/mysql -uroot --protocol=SOCKET <<SQL

ALTER USER 'root'@'localhost'
  IDENTIFIED VIA unix_socket
  OR mysql_native_password USING PASSWORD('${MYSQL_PASS}');

DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

DROP USER IF EXISTS 'root'@'%';
DROP USER IF EXISTS 'root'@'127.0.0.1';
DROP USER IF EXISTS 'root'@'::1';

DROP DATABASE IF EXISTS test;

FLUSH PRIVILEGES;
SQL
  echo -e "\n✅ MariaDB initialization complete. Root password:：\033[1;32m${MYSQL_PASS}\033[0m"
  cd /home/wwwroot/default
    rm -rf phpmyadmin phpmyadmin.zip
    
    wget -c https://files.phpmyadmin.net/phpMyAdmin/5.2.3/phpMyAdmin-5.2.3-all-languages.zip -O phpmyadmin.zip
    apt install -y unzip
    unzip phpmyadmin.zip -d ./
    mv phpMyAdmin* phpmyadmin
    rm -f phpmyadmin.zip
    chown -R www:www /home/wwwroot
  
  cd /root

apt remove --purge -y 'groonga*' 'libgroonga*'
apt -f install -y
apt autoremove -y
apt clean
rm -rf /usr/local/bin/groonga \
            /usr/local/bin/groonga-* \
            /usr/local/lib/libgroonga* \
            /usr/local/lib/groonga \
            /usr/local/include/groonga \
            /usr/local/share/groonga

rm -rf /usr/local/bin/mroonga \
            /usr/local/bin/mroonga-* \
            /usr/local/lib/libmroonga* \
            /usr/local/lib/mroonga \
            /usr/local/include/mroonga \
            /usr/local/share/mroonga
rm -f /etc/ld.so.conf.d/groonga.conf
rm -f /etc/ld.so.conf.d/mroonga.conf
ldconfig
rm -rf /root/groonga
rm -rf /root/mroonga
apt-get install -y \
  build-essential cmake ninja-build pkg-config \
  liblz4-dev libzstd-dev libxxhash-dev \
  libevent-dev libpcre2-dev libonig-dev libmsgpack-dev \
  libmecab-dev mecab-ipadic-utf8 \
  libssl-dev zlib1g-dev



 wget https://packages.groonga.org/source/groonga/groonga-latest.tar.gz -O groonga.tar.gz
  mkdir -p groonga
  tar -zxvf groonga.tar.gz --strip-components=1 -C groonga
cd groonga

cmake -S . -B build -G Ninja \
  -DGRN_WITH_MRUBY=OFF \
  -DGRN_WITH_APACHE_ARROW=OFF \
  --preset=release-maximum



cmake --build build -j"$(nproc)"
cmake --install build
ldconfig

groonga --version

apt install -y   groonga-token-filter-stem groonga-tokenizer-mecab libgroonga-dev groonga-normalizer-mysql

  wget https://packages.groonga.org/source/mroonga/mroonga-latest.tar.gz -O mroonga.tar.gz
  mkdir -p mroonga
  tar -zxvf mroonga.tar.gz --strip-components=1 -C mroonga
  cd mroonga
  mariadb_version=$(/usr/local/mariadb/bin/mysql_config --version)
  cmake \
      -S . \
      -B build \
      -GNinja \
      -DGRN_LIBRARIES=/usr/lib/x86_64-linux-gnu/libgroonga.so \
      -DMRN_DEFAULT_TOKENIZER=TokenBigramSplitSymbolAlphaDigit \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local/mroonga \
      -DMYSQL_BUILD_DIR=/root/mariadb-$mariadb_version/build \
      -DMYSQL_CONFIG=/usr/local/mariadb/bin/mysql_config \
      -DMYSQL_SOURCE_DIR=/root/mariadb-$mariadb_version
  cmake --build build -j"$(nproc)"
  cmake --install build

  /usr/local/mariadb/bin/mysql -u root < /usr/local/mroonga/share/mroonga/install.sql

  cd /root

 
  rm -f /etc/apt/sources.list.d/apache-arrow*.list /etc/apt/sources.list.d/apache-arrow*.sources
  rm -f /etc/apt/sources.list.d/groonga*.list /etc/apt/sources.list.d/groonga*.sources
  rm -f /usr/share/keyrings/apache-arrow-archive-keyring.gpg
  rm -f /usr/share/keyrings/groonga-archive-keyring.gpg
  rm -f /etc/apt/trusted.gpg.d/apache-arrow*.gpg /etc/apt/trusted.gpg.d/groonga*.gpg
  rm -f /etc/apt/preferences.d/groonga.pref
  apt-get update

else
  echo "Do not install MariaDB"
fi
apt --fix-broken install -y
apt autoremove -y


auto_optimize_services() {
  echo "=================================================="
  echo " Automatic Optimization of WNMP (WebDav / Nginx / PHP-FPM / MariaDB)" 
  echo "=================================================="

  CPU_CORES=$(nproc)
  MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

  echo "CPU: ${CPU_CORES} cores"
  echo "MEM: ${MEM_TOTAL} MB"
  echo


  PHP_FPM_CONF="/usr/local/php/etc/php-fpm.conf"
  if [ -f "$PHP_FPM_CONF" ]; then
    if [ "$MEM_TOTAL" -lt 2000 ]; then
      PM_MAX_CHILDREN=5
    elif [ "$MEM_TOTAL" -lt 8000 ]; then
      PM_MAX_CHILDREN=20
    else
      PM_MAX_CHILDREN=50
    fi
    PM_START=$((PM_MAX_CHILDREN/3)); [ "$PM_START" -lt 1 ] && PM_START=1
    PM_MIN=$((PM_START/2)); [ "$PM_MIN" -lt 1 ] && PM_MIN=1
    PM_MAX=$((PM_START*2))
    sed -i "s/pm.max_children =.*/pm.max_children = ${PM_MAX_CHILDREN}/" "$PHP_FPM_CONF"
    sed -i "s/pm.start_servers =.*/pm.start_servers = ${PM_START}/" "$PHP_FPM_CONF"
    sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = ${PM_MIN}/" "$PHP_FPM_CONF"
    sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = ${PM_MAX}/" "$PHP_FPM_CONF"
    echo "[PHP-FPM] max_children=${PM_MAX_CHILDREN} start=${PM_START} min=${PM_MIN} max=${PM_MAX}"
  else
    echo "[PHP-FPM] No configuration detected, skipping." 
  fi


  MYSQL_CONF="/etc/my.cnf"
  if [ -f "$MYSQL_CONF" ]; then
    if [ "$MEM_TOTAL" -lt 2000 ]; then
      INNODB_BUFFER="256M"
    elif [ "$MEM_TOTAL" -lt 8000 ]; then
      INNODB_BUFFER="1G"
    else
      INNODB_BUFFER="2G"
    fi
    sed -i "s/^innodb_buffer_pool_size =.*/innodb_buffer_pool_size = ${INNODB_BUFFER}/" "$MYSQL_CONF"
   
    if grep -q "^tmp_table_size" "$MYSQL_CONF"; then
      if [ "$MEM_TOTAL" -lt 2000 ]; then TMP_SIZE="64M"
      elif [ "$MEM_TOTAL" -lt 8000 ]; then TMP_SIZE="128M"
      else TMP_SIZE="256M"; fi
      sed -i "s/^tmp_table_size =.*/tmp_table_size = ${TMP_SIZE}/" "$MYSQL_CONF"
      sed -i "s/^max_heap_table_size =.*/max_heap_table_size = ${TMP_SIZE}/" "$MYSQL_CONF" || true
    fi
    echo "[MariaDB] innodb_buffer_pool_size=${INNODB_BUFFER}"
  else
    echo "[MariaDB] No configuration detected, skipping." 
  fi

  systemctl restart nginx 2>/dev/null && echo "[OK] nginx Restart Succeeded" || echo "[WARN] nginx Restart Failed or not installed" 
  systemctl restart php-fpm 2>/dev/null && echo "[OK] php-fpm Restart Succeeded" || echo "[WARN] php-fpm Restart Failed or not installed" 
  systemctl restart mariadb 2>/dev/null && echo "[OK] mariadb Restart Succeeded" || echo "[WARN] mariadb Restart Failed or not installed"

  echo "================= Optimization Results Report =================" 
  
  [ -f "$PHP_FPM_CONF" ] && { echo "[PHP-FPM]"; grep -E "pm.max_children|pm.start_servers|pm.min_spare_servers|pm.max_spare_servers|request_slowlog_timeout" "$PHP_FPM_CONF" | sed 's/^[ \t]*//'; echo; }
  [ -f "$MYSQL_CONF" ] && { echo "[MariaDB]"; grep -E "innodb_buffer_pool_size|max_connections|tmp_table_size|max_heap_table_size" "$MYSQL_CONF" | sed 's/^[ \t]*//'; echo; }
  echo "================= Optimization Complete =================" 
}



auto_optimize_services


wnmp_kernel_tune
