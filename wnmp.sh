#!/usr/bin/env bash
# WNMP Setup Script
# Copyright (C) 2025 wnmp.org
# Website: https://wnmp.org
# License: GNU General Public License v3.0 (GPLv3)
# Version: 1.08

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

if [[ -t 1 && -z "${WNMP_UNDER_SCRIPT:-}" ]]; then
  if command -v script >/dev/null 2>&1; then
    export WNMP_UNDER_SCRIPT=1
    exec script -qef -c "env SYSTEMD_COLORS=1 SYSTEMD_PAGER=cat bash '$0' $*" "$LOGFILE"
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
green  "============================================================"
echo
sleep 1

usage() {
  cat <<'USAGE'
用法:
  bash wnmp.sh               # 正常安装
  bash wnmp.sh status        # 查看状态
  bash wnmp.sh sshkey        # ssh密钥登录
  bash wnmp.sh webdav        # 添加webdav账号
  bash wnmp.sh default       # 默认站点域名与证书
  bash wnmp.sh vhost         # 创建虚拟主机（含证书）
  bash wnmp.sh tool          # 仅做内核/网络调优
  bash wnmp.sh restart       # 重启服务
  bash wnmp.sh remove        # 卸载
  bash wnmp.sh renginx       # 卸载nginx
  bash wnmp.sh rephp         # 卸载php
  bash wnmp.sh remariadb     # 卸载mariadb
  bash wnmp.sh wslinit       # wsl开启ssh服务
  bash wnmp.sh -h|--help     # 查看帮助
USAGE
}


wslinit(){

  if [ "$(id -u)" -ne 0 ]; then
  echo "[-] 请用 root 或 sudo 运行："
  echo "    sudo bash $0"
  exit 1
fi

echo "[1/7] 备份原有 sources.list ..."
if [ -f /etc/apt/sources.list ]; then
  cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d-%H%M%S)
fi

echo "[2/7] 写入阿里云 Debian 13 (trixie) 国内源 ..."
cat >/etc/apt/sources.list <<'EOF'
deb http://mirrors.aliyun.com/debian/ trixie main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ trixie-backports main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security/ trixie-security main contrib non-free non-free-firmware
EOF

echo "[2.1/7] 可选：移走 sources.list.d 里的其它源，避免混源 ..."
if [ -d /etc/apt/sources.list.d ]; then
  mkdir -p /etc/apt/sources.list.d/backup
  mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/backup/ 2>/dev/null || true
  mv /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/backup/ 2>/dev/null || true
fi

echo "[3/7] 更新索引并升级系统 ..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt -y full-upgrade

echo "[4/7] 安装常用工具和 openssh-server ..."
apt install -y \
  build-essential \
  ca-certificates \
  curl wget unzip git cmake pkg-config \
  htop net-tools \
  openssh-server

install -d -m 0755 -o root -g root /run/sshd

ssh-keygen -A

# 确保 CA 证书生效（有些环境会用到 https）
update-ca-certificates || true

echo "[5/7] 配置 SSH：允许 root 登录 + 密码登录 ..."

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

echo "[6/7] 重启 SSH 服务 ..."

# WSL2 默认没有 systemd，用 service 优先
if command -v service >/dev/null 2>&1; then
  service sshd restart || true
fi

# 如果系统启用了 systemd，也顺手 enable 一下（物理/云服务器有用）
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable sshd >/dev/null 2>&1 || true
  systemctl restart sshd >/dev/null 2>&1 || true
fi

echo "[7/7] 设置 root 密码（请按提示输入两遍新密码） ..."
passwd root

echo "[7.1/7] 设置默认用户为 root（写入 /etc/wsl.conf） ..."

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
echo
echo "================= 完成 ================="
echo "[OK] 已切换到阿里云 Debian 13 (trixie) 国内源。"
echo "[OK] 系统已升级，常用工具和 openssh-server 已安装。"
echo "[OK] SSH 已允许 root + 密码登录。"
echo
echo "小提示："
echo "  1) 在 WSL2 里，如果 ssh 没在跑，可以手动启动："
echo "       systemctl start sshd"
echo
echo "  2) 在本机测试连接（WSL 内部）可以用："
echo "       ssh root@127.0.0.1"
echo
echo "  3) 如果是云服务器，用："
echo "       ssh root@服务器IP"
echo
echo "  4) 如需恢复旧源，可看备份："
echo "       /etc/apt/sources.list.bak.*"
echo "  5) 一定要配合开机自启动脚本，重启一次硬件电脑后才能正常使用"

echo "========================================"

}



is_lan() {
  local local_ip
  local_ip=$(hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /^127\./) {print $i; exit}}' 2>/dev/null)
  if [[ -z "$local_ip" ]]; then
    IS_LAN=1
    return 0
  fi
  if [[ "$local_ip" =~ ^10\. ]] || \
     [[ "$local_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
     [[ "$local_ip" =~ ^192\.168\. ]] || \
     [[ "$local_ip" =~ ^127\. ]] || \
     [[ "$local_ip" =~ ^169\.254\. ]]; then
    IS_LAN=1
  else
    IS_LAN=0
  fi
  return 0
}

is_lan








status() {

  systemctl --no-pager status nginx
  systemctl --no-pager status php-fpm
  systemctl --no-pager status mariadb

  exit 0
}
restart() {
  systemctl restart nginx
  systemctl --no-pager status nginx

  systemctl restart php-fpm
  systemctl --no-pager status php-fpm

  systemctl restart mariadb
  systemctl --no-pager status mariadb

  echo "服务重启完成"
  exit 0
}

webdav() {
  local domain user pass passwd_file ans

  read -rp "是否开启 WebDAV？[y/N] " ans
  ans="${ans:-N}"
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "[webdav] 已跳过。"
    return 0
  fi
  
  while :; do
    read -rp "站点存在多个域名的，请输入最终重定向域名（例如：wwww.example.com）:" domain
    [[ -n "$domain" ]] && break
    echo "[webdav][WARN] 域名不能为空。"
  done


  read -rp "是否开启 公开目录默认（否）？[y/N] " ans
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
    echo "[webdav][ERROR] 未找到配置：$VHOST_DIR/${domain_lc}.conf 或 ${domain_lc#www.}.conf"
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
    echo "[webdav][ERROR] 未找到 nginx 可执行文件；建议 ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx"
    return 1
  fi

  backup="${conf_path}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$conf_path" "$backup" || { echo "[webdav][ERROR] 备份失败：$backup"; return 1; }

 
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
    echo "[webdav] 已移除 include enable-php.conf;（禁止 PHP 执行）"
    insert_once "$conf_path" "include download.conf;"
    echo "[webdav] 已确保 include download.conf;"
  else

    sed -i '/^[[:space:]]*include[[:space:]]\+download\.conf;[[:space:]]*$/d' "$conf_path"
    echo "[webdav] 已移除 include download.conf;"
    insert_once "$conf_path" "include enable-php.conf;"
    echo "[webdav] 已确保 include enable-php.conf;"
  fi


  if "$NGINX_BIN" -t; then
    if systemctl >/dev/null 2>&1; then
      systemctl reload nginx 2>/dev/null || "$NGINX_BIN" -s reload
    else
      "$NGINX_BIN" -s reload
    fi
    echo "[webdav] ✅ 配置已生效。"
  else
    echo "[webdav][ERROR] nginx -t 失败，回滚到：$backup"
    cp -a "$backup" "$conf_path" >/dev/null 2>&1 || true
    return 1
  fi


  local passwd_dir="/home/passwd"
  mkdir -p "$passwd_dir"
  passwd_file="${passwd_dir}/.${domain}"

  while :; do
    read -rp "请输入 WebDAV 账号名称：" user
    [[ -n "$user" ]] && break
    echo "[webdav][WARN] 账号不能为空。"
  done

  read -rs -p "请输入 WebDAV 密码：" pass; echo

  if [[ -f "$passwd_file" ]]; then
    echo "[webdav] 检测到已存在的密码文件，将追加账号..."
    htpasswd -bB "$passwd_file" "$user" "$pass"
  else
    echo "[webdav] 未发现密码文件，正在创建..."
    htpasswd -cbB "$passwd_file" "$user" "$pass"
  fi

  chown www:www "$passwd_file" 2>/dev/null || true
  chmod 640 "$passwd_file" 2>/dev/null || true

  echo "[webdav] ✅ 已写入账号：$user -> $passwd_file"
}






default() {
  if [[ "$IS_LAN" -eq 1 ]]; then
    red "[env] 当前为内网环境，将跳过证书申请。"
    read -rp "是否强制申请证书？[y/N] " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ [Yy]$ ]]; then
      green "[env] 已选择强制申请证书。"
      IS_LAN=0
    else
      red "[env] 保持跳过证书申请。"
    fi
  else
    green "[env] 检测到公网环境，可正常申请证书。"
  fi
  if [[ "$IS_LAN" -eq 1 ]]; then
  red "[env] 当前为内网环境，将跳过证书申请。"
  exit 0
  fi
  read -rp "[STEP1] 请输入域名: " DOMAIN_LINE
  if [[ -z "$DOMAIN_LINE" ]]; then
    
    echo "[WARN] 域名不能为空"
    return 0
  else
    echo "[STEP1] 输入域名: ${DOMAIN_LINE}"
  fi

  FIRST_DOMAIN=$(echo "$DOMAIN_LINE" | awk '{print $1}')
  MAP_REGEX=$(printf "%s" "$DOMAIN_LINE" | sed -e 's/\./\\./g' -e 's/[[:space:]]\+/\|/g')
  MAP_REGEX="^(${MAP_REGEX})$"

  echo "[STEP2] 写 nginx.conf + 注入 map"
  

  cat >/usr/local/nginx/nginx.conf <<'NGINX_CONF'
user  www www;
worker_processes auto;
worker_rlimit_nofile 1000000;
pid /usr/local/nginx/nginx.pid;

error_log  /home/wwwlogs/nginx_error.log crit;

events {
    worker_connections 65535;
    use epoll;
}

http {
    __MAP_BLOCK_PLACEHOLDER__

    include       mime.types;
    default_type  application/octet-stream;
    dav_ext_lock_zone zone=webdav_locks:10m;
    aio threads;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout   10s;
    keepalive_requests  100000;

    client_body_temp_path /usr/local/nginx/client_body_temp 1 2;
    client_max_body_size 10g;
    client_body_buffer_size 512k;
    client_header_timeout 300s;
    client_body_timeout   1800s;
    send_timeout          1800s;

    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2c0f:f248::/32;
    set_real_ip_from 2a06:98c0::/29;
    real_ip_header CF-Connecting-IP;
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
        listen 443 ssl default_server reuseport;
        http2 on;
        server_name _;

        root  /home/wwwroot/default;
        index index.html index.php;

        if ($is_allowed_host = 0) { return 403; }

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
        ssl_session_cache   shared:SSL:20m;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5:!RC4:!3DES;
        ssl_prefer_server_ciphers off;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        ssl_stapling on;
        ssl_stapling_verify on;

        autoindex_exact_size off;
        autoindex_localtime on;

        include enable-php.conf;

        location /nginx_status { stub_status on; access_log off; }

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
        location ~ /\.(?!well-known) { deny all; }

        location = /phpmyadmin { return 301 /phpmyadmin/; }
        location ^~ /phpmyadmin/ {
            include enable-php.conf;
            auth_basic "WebDAV Authentication";
            auth_basic_user_file /home/passwd/.default;
        }

        access_log off;
    }

    include vhost/*.conf;
}
NGINX_CONF

  sed -i "s#__MAP_BLOCK_PLACEHOLDER__#map \$host \$is_allowed_host {\n        default 0;\n        ~\\(${MAP_REGEX}\\) 1;\n    }#g" /usr/local/nginx/nginx.conf
  echo "[STEP2] map 正则：${MAP_REGEX}"

  echo "[STEP4] 探测 acme.sh"
  ACME_HOME="${ACME_HOME:-$HOME/.acme.sh}"
  ACME_BIN=""
  if command -v acme.sh >/dev/null 2>&1; then
    ACME_BIN="$(command -v acme.sh)"
  elif [ -x "$ACME_HOME/acme.sh" ]; then
    ACME_BIN="$ACME_HOME/acme.sh"
  fi
  if [ -z "$ACME_BIN" ]; then
    echo "[STEP4] 安装 acme.sh ..."
    curl -fsSL https://get.acme.sh | sh
    ACME_BIN="$HOME/.acme.sh/acme.sh"
    ACME_HOME="$HOME/.acme.sh"
  fi
  echo "[STEP4] ACME_BIN=$ACME_BIN"
  echo "[STEP4] ACME_HOME=$ACME_HOME"
  "$ACME_BIN" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

  echo "[STEP5] 读取 CF 凭据（环境优先，其次 account.conf）"
  token_file="$ACME_HOME/account.conf"
  [ -f "$token_file" ] && echo "[STEP5] account.conf: $token_file 存在" || echo "[STEP5] account.conf: 不存在"


  CF_Token_val="${CF_Token-}"
  if [ -z "$CF_Token_val" ] && [ -f "$token_file" ]; then
    CF_Token_val="$(grep -E "^SAVED_CF_Token=" "$token_file" 2>/dev/null | head -n1 | cut -d"'" -f2 2>/dev/null || true)"
  fi

  CF_Key_val="${CF_Key-}"
  if [ -z "$CF_Key_val" ] && [ -f "$token_file" ]; then
    CF_Key_val="$(grep -E "^SAVED_CF_Key=" "$token_file" 2>/dev/null | head -n1 | cut -d"'" -f2 2>/dev/null || true)"
  fi

  CF_Email_val="${CF_Email-}"
  if [ -z "$CF_Email_val" ] && [ -f "$token_file" ]; then
    CF_Email_val="$(grep -E "^SAVED_CF_Email=" "$token_file" 2>/dev/null | head -n1 | cut -d"'" -f2 2>/dev/null || true)"
  fi

  dns_cf_script="$ACME_HOME/dnsapi/dns_cf.sh"
  [ -f "$dns_cf_script" ] && echo "[STEP5] dns_cf.sh: found ($dns_cf_script)" || echo "[STEP5] dns_cf.sh: missing"


  DNS_CF_OK=0
  if [ -f "$dns_cf_script" ]; then
    if [ -n "$CF_Token_val" ] || { [ -n "$CF_Key_val" ] && [ -n "$CF_Email_val" ]; }; then
      DNS_CF_OK=1
    fi
  fi


  short() { printf "%s" "$1" | cut -c1-6; }
  echo "[STEP5] CF_Token: $( [ -n "$CF_Token_val" ] && printf "%s******" "$(short "$CF_Token_val")" || echo "<none>" )"
  echo "[STEP5] CF_Key  : $( [ -n "$CF_Key_val"   ] && printf "%s******" "$(short "$CF_Key_val")"   || echo "<none>" )"
  echo "[STEP5] CF_Email: $( [ -n "$CF_Email_val" ] && printf "%s"        "$CF_Email_val"            || echo "<none>" )"
  echo "[STEP5] DNS_CF_OK: $DNS_CF_OK"

  echo "[STEP6] 尝试签发 ($FIRST_DOMAIN, EC-256)"
  CF_OK=0
  if [ "$DNS_CF_OK" -eq 1 ]; then
    echo "[STEP6-DNS] 使用 Cloudflare DNS（dns_cf）"
    if [ -n "$CF_Token_val" ]; then
      CF_Token="$CF_Token_val" \
      "$ACME_BIN" --issue --dns dns_cf -d "$FIRST_DOMAIN" --keylength ec-256 --force  || true
      [ $? -eq 0 ] && CF_OK=1
    else
      CF_Key="$CF_Key_val" CF_Email="$CF_Email_val" \
      "$ACME_BIN" --issue --dns dns_cf -d "$FIRST_DOMAIN" --keylength ec-256 --force  || true
      [ $? -eq 0 ] && CF_OK=1
    fi
    [ "$CF_OK" -eq 1 ] && echo "[STEP6-DNS] 成功" || echo "[STEP6-DNS] 失败，准备 webroot 回落"
  else
    echo "[STEP6] 无可用 CF 凭据或缺少 dns_cf.sh，直接 webroot"
  fi

  if [ "$CF_OK" -ne 1 ]; then
    echo "[STEP6-WEBROOT] --webroot /home/wwwroot/default"
    "$ACME_BIN" --issue -w /home/wwwroot/default -d "$FIRST_DOMAIN" --keylength ec-256 --force  || {
      echo "[ERROR] webroot 申请失败"; return 2;
    }
  fi

  echo "[STEP7] 安装证书到固定路径并 reload"
  "$ACME_BIN" --install-cert -d "$FIRST_DOMAIN" --ecc \
    --key-file       /usr/local/nginx/ssl/default/key.pem \
    --fullchain-file /usr/local/nginx/ssl/default/cert.pem \
    --reloadcmd     '/usr/local/nginx/sbin/nginx -t && /usr/local/nginx/sbin/nginx -s reload' || {
      echo "[ERROR] 安装/重载失败"; return 3;
    }

  echo "[DONE] 默认站点证书已就绪：/usr/local/nginx/ssl/default/{cert.pem,key.pem}"
}



vhost() {
  if [[ "$IS_LAN" -eq 1 ]]; then
    red "[env] 当前为内网环境，将跳过证书申请。"
    read -rp "是否强制申请证书？[y/N] " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ [Yy]$ ]]; then
      green "[env] 已选择强制申请证书。"
      IS_LAN=0
    else
      red "[env] 保持跳过证书申请。"
    fi
  else
    green "[env] 检测到公网环境，可正常申请证书。"
  fi
  if ! (echo $BASH_VERSION >/dev/null 2>&1); then
    echo "[vhost][ERROR] 请用 bash 执行此脚本。"; return 1
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
    ssl_session_cache   shared:SSL:20m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!RC4:!3DES;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

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
  read -rp "请输入要创建的域名（可多个，空格分隔）： " -a DOMAINS
  [[ ${#DOMAINS[@]} -gt 0 ]] || { echo "[vhost] 未输入域名，退出。"; return 1; }

  local _filtered=()
  local d
  for d in "${DOMAINS[@]}"; do
    d="$(echo -n "$d" | tr -d '[:space:]')"
    [[ -n "$d" ]] && _filtered+=("$d")
  done
  DOMAINS=("${_filtered[@]}")
  [[ ${#DOMAINS[@]} -gt 0 ]] || { echo "[vhost] 未输入有效域名，退出。"; return 1; }

  local primary="${DOMAINS[0]}"
  local others=()
  [[ ${#DOMAINS[@]} -gt 1 ]] && others=("${DOMAINS[@]:1}")


  local issue_cert="n"
  local ans
  read -rp "是否现在为这些域名申请证书？[Y/n] " ans
  ans="${ans:-Y}"
  [[ "$ans" == [Yy] ]] && issue_cert="y"
  if [[ "$issue_cert" == "y" && -z "$acme_bin" ]]; then
     echo "[vhost][WARN] 未检测到 acme.sh，将跳过证书签发。"; issue_cert="n"
  fi
  if [[ "$IS_LAN" -eq 1 ]]; then
      echo "[env] 当前为内网环境，将跳过证书申请。"; issue_cert="n"
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
    local cert="${dir}/cert.pem"; local key="${dir}/key.pem"
    sed -i \
      -e "s#ssl_certificate[[:space:]]\+/usr/local/nginx/ssl/default/cert.pem;#ssl_certificate     ${cert};#g" \
      -e "s#ssl_certificate_key[[:space:]]\+/usr/local/nginx/ssl/default/key.pem;#ssl_certificate_key ${key};#g" \
      "$conf"
    if ! grep -qE "ssl_certificate[[:space:]]+${cert//\//\\/};" "$conf"; then
      local _SSL_LINES
      _SSL_LINES="$(cat <<EOF
    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
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
  echo "[vhost] 已生成配置：$conf"


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
    read -rp "是否已解析域名到本机IP？(输入 yes 确认): " ans
    if [[ "${ans,,}" != "yes" ]]; then
      echo "[safe] 已取消操作。未作任何更改。"; return 0
    fi

    local CF_Token_val="" dns_cf_ok=0
    CF_Token_val="$(get_cf_token || true)"
    [[ -n "$CF_Token_val" && -f "$acme_home/dnsapi/dns_cf.sh" ]] && dns_cf_ok=1
    echo "[vhost][INFO] CF_Token: $( [[ -n "${CF_Token_val:-}" ]] && echo "${CF_Token_val:0:6}******" || echo "<none>" )"
    echo "[vhost][INFO] dns_cf.sh: $( [[ $dns_cf_ok -eq 1 ]] && echo found || echo missing )"

    mkdir -p "$ssl_dir"
    local -a args
    if [[ $dns_cf_ok -eq 1 ]]; then
      echo "[vhost][ISSUE] 使用 dns_cf 为所有域名一次性签发..."
      args=( --issue --dns dns_cf -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      CF_Token="$CF_Token_val" "$acme_bin" "${args[@]}" --keylength ec-256 || true
    else
      echo "[vhost][ISSUE] 使用 webroot 为所有域名一次性签发..."
      args=( --issue -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      args+=( --webroot "$site_root" --keylength ec-256 --debug 2 )
      "$acme_bin" "${args[@]}" || true
    fi

    "$acme_bin" --install-cert -d "$primary" \
      --ecc \
      --key-file       "$ssl_dir/key.pem" \
      --fullchain-file "$ssl_dir/cert.pem" \
      --reloadcmd      "true" || true

    if [[ -s "$ssl_dir/key.pem" && -s "$ssl_dir/cert.pem" ]]; then
      cert_success=1
      echo "[vhost][OK] 证书就绪：$primary -> $ssl_dir"
      ensure_https_core "$conf"
      update_ssl_paths_single_dir "$conf" "$ssl_dir"
    else
      echo "[vhost][WARN] 证书签发未成功，将按“未申请证书”处理。"
    fi
  fi

  remove_old_redirects "$conf"
  if [[ "$cert_success" -eq 1 ]]; then
    if [[ "$has_www_peer" -eq 1 ]]; then
      inject_after_server_name "$conf" "$REDIR_WWW_SSL"
      echo "[vhost][HTTPS] 注入：强制 www + 单次跳转（含 HTTP→HTTPS）"
    else
      inject_after_server_name "$conf" "$REDIR_PLAIN_SSL"
      echo "[vhost][HTTPS] 注入：HTTP→HTTPS 跳转"
    fi
  else
    if [[ "$has_www_peer" -eq 1 ]]; then
      strip_ssl_lines "$conf"
      inject_after_server_name "$conf" "$REDIR_WWW_NO_SSL"
      echo "[vhost][HTTP] 注入：仅 HTTP 下的 www 规范化"

    fi
    
  fi


  if /usr/local/nginx/sbin/nginx -t; then
    /usr/local/nginx/sbin/nginx -s reload || systemctl reload nginx
    echo "[vhost] Nginx 已重载。"
  else
    echo "[vhost][ERROR] nginx 配置检查失败。"; return 1
  fi

  if [[ "$cert_success" -eq 1 ]]; then
    webdav
  else
    echo "[vhost][INFO] 跳过 webdav（因未开启/未成功签发证书）。"
  fi

  echo "[vhost] 完成。"
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
         /root/php-*/ /root/apcu* /root/inotify* /root/php-*.tar.* /usr/local/src/php-* /root/swoole*

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
    echo "[mariadb] 未发现 MariaDB 相关组件，跳过备份与清理。"
  else
 
    backup_done=0
    ts="$(date +%Y%m%d_%H%M%S)"
    backup_file="/home/all_databases_backup_${ts}.sql.gz"

   
    mysql_cmd_base=(mysql --connect-timeout=3 --protocol=SOCKET -uroot)
    mysqldump_cmd_base=(mysqldump --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)

    if [ -f /root/.my.cnf ]; then
      mysql_cmd_base=(mysql --defaults-file=/root/.my.cnf --connect-timeout=3)
      mysqldump_cmd_base=(mysqldump --defaults-file=/root/.my.cnf --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)
    fi

    if ! "${mysql_cmd_base[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
    
      mysql_cmd_base=(mysql -h127.0.0.1 -P3306 -uroot --connect-timeout=3)
      mysqldump_cmd_base=(mysqldump -h127.0.0.1 -P3306 -uroot --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)
     
      if [ -f /root/.my.cnf ]; then
        mysql_cmd_base=(mysql --defaults-file=/root/.my.cnf -h127.0.0.1 -P3306 --connect-timeout=3)
        mysqldump_cmd_base=(mysqldump --defaults-file=/root/.my.cnf -h127.0.0.1 -P3306 --single-transaction --default-character-set=utf8mb4 --routines --events --flush-privileges --all-databases)
      fi
    fi

    if "${mysql_cmd_base[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
      echo "[backup] 检测到可用的 MariaDB，开始全库备份：${backup_file}"
      mkdir -p /home
    
      if command -v ionice >/dev/null 2>&1; then
        ionice -c2 -n7 nice -n 19 "${mysqldump_cmd_base[@]}" | gzip -c > "${backup_file}"
      else
        nice -n 19 "${mysqldump_cmd_base[@]}" | gzip -c > "${backup_file}"
      fi
    
      if [ -s "${backup_file}" ]; then
        echo "[backup] 备份完成：${backup_file}"
        backup_done=1
      else
        echo "[backup][WARN] 备份文件为空，可能备份失败：${backup_file}"
      fi
    else
      echo "[backup][WARN] 无法连接 MariaDB，跳过备份（可能无 root 凭据或服务未就绪）。"
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
      echo "[done] MariaDB 已清理，备份保存在：${backup_file}"
    else
      echo "[done] MariaDB 已清理（未生成备份或备份失败）。"
    fi
  fi
}



remove(){
  purge_nginx
  purge_php
  purge_mariadb
  echo "nginx,php,mariadb已全部清理干净"
  exit 0

}
renginx(){
  purge_nginx
  echo "nginx已清理干净"
  exit 0

}

rephp(){
  purge_php
  echo "php已清理干净"
  exit 0

}

remariadb(){
  purge_mariadb
  echo "mariadb已清理干净"
  exit 0

}



KERNEL_TUNE_ONLY=0




sshkey() {
  if [[ "$IS_LAN" -eq 1 ]]; then
    red "[env] 当前为内网环境，将跳过证书申请。"
    read -rp "是否强制申请证书？[y/N] " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ [Yy]$ ]]; then
      green "[env] 已选择强制申请证书。"
      IS_LAN=0
    else
      red "[env] 保持跳过证书申请。"
    fi
  else
    green "[env] 检测到公网环境，可正常申请证书。"
  fi
  set -euo pipefail
  if [[ "$IS_LAN" -eq 1 ]]; then
    echo "[env] 当前为内网环境，已跳过证书申请。"
    exit 0
  fi
  echo
  echo "====================================================================="
  echo "⚠️  强提醒：在你确认【已把私钥保存到你自己的电脑】之前"
  echo "⚠️  请不要断开当前 SSH 会话，否则你将无法再次登录服务器！"
  echo "====================================================================="
  echo
  read -rp "是否继续执行并启用仅 root 密钥登录？(输入 yes 确认): " ans
  if [[ "${ans,,}" != "yes" ]]; then
    echo "[safe] 已取消操作。未作任何更改。"
    return 0
  fi


  local SSHD_BIN=""
  if SSHD_BIN="$(command -v sshd 2>/dev/null || true)"; [[ -z "${SSHD_BIN}" ]]; then
    [[ -x /usr/sbin/sshd ]] && SSHD_BIN="/usr/sbin/sshd"
  fi
  [[ -z "${SSHD_BIN}" && -x /sbin/sshd ]] && SSHD_BIN="/sbin/sshd"
  if [[ -z "${SSHD_BIN}" ]]; then
    echo "[safe][ERROR] 未找到 sshd 可执行文件，请先安装 openssh-server。"
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

  echo "[safe] 正在为 root 用户配置【仅密钥登录】..."


  if grep -Eq '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+[[:space:]]+[^#]+' "$SSHD_MAIN"; then
    cp -a "$SSHD_MAIN" "${SSHD_MAIN}.prelint-${NOW}"
    sed -i -E 's/^([[:space:]]*ClientAliveInterval)[[:space:]]+[0-9]+.*/\1 120/' "$SSHD_MAIN"
    echo "[safe] 已修复非法尾注：ClientAliveInterval 行已归一化为 'ClientAliveInterval 120'"
  fi


  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  chown -R root:root "${SSH_DIR}"


  if ! ls /etc/ssh/ssh_host_*key >/dev/null 2>&1; then
    echo "[safe] 未发现主机 HostKeys，正在生成（ssh-keygen -A）..."
    ssh-keygen -A
  fi


  local PASSPHRASE_OPT=""
  echo
  read -rp "是否为新密钥添加口令保护（登录时需输入该口令）？[y/N]: " setpass
  if [[ "${setpass,,}" =~ ^(y|yes)$ ]]; then
    echo "[safe] 将为新密钥设置口令..."
    PASSPHRASE_OPT="-N"
  else
    PASSPHRASE_OPT="-N \"\""
  fi

 
  if [[ -f "${PRIV_KEY}" || -f "${PUB_KEY}" ]]; then
    echo "[safe] 检测到已有 root 密钥对，备份中..."
    [[ -f "${PRIV_KEY}" ]] && mv -f "${PRIV_KEY}" "${PRIV_KEY}.bak-${NOW}"
    [[ -f "${PUB_KEY}"  ]] && mv -f "${PUB_KEY}"  "${PUB_KEY}.bak-${NOW}"
  fi

  echo "[safe] 生成 ED25519 密钥对..."
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
  if ! grep -qF "$(cat "${PUB_KEY}")" "${AUTH_KEYS}"; then
    cat "${PUB_KEY}" >> "${AUTH_KEYS}"
  fi


  cp -a "${SSHD_MAIN}" "${SSHD_BAK}"
  echo "[safe] 已备份主配置：${SSHD_BAK}"

  mkdir -p "${OVR_DIR}"
  if [ "$(find "${OVR_DIR}" -type f | wc -l)" -gt 0 ]; then
    mkdir -p "${OVR_BACKUP_DIR}"
    find "${OVR_DIR}" -maxdepth 1 -type f -print -exec mv -f {} "${OVR_BACKUP_DIR}/" \;
    echo "[safe] 已备份并清空 /etc/ssh/sshd_config.d -> ${OVR_BACKUP_DIR}"
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


  echo "[safe] 检测 sshd 配置语法 (${SSHD_BIN} -t)..."
  if ! err="$("${SSHD_BIN}" -t 2>&1)"; then
    echo "[safe][ERROR] sshd -t 失败："; echo "$err"
    echo "[safe] 回滚中..."
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
  echo "[safe] 公钥指纹（SHA256）："
  ssh-keygen -lf "${PUB_KEY}" -E sha256 | awk '{print " - "$0}'
  echo
  echo "==================  复制以下【私钥文件内容】到你本地(保存为例子:test.key,导入到例子xshell等客户端后可以root密钥登录)  =================="
  cat "${PRIV_KEY}"
  echo
  echo "==================  复制结束  ================="
  echo
  echo "[safe] 一行版私钥（已存入服务器${AUTH_KEYS}）："
  if base64 --help 2>&1 | grep -q -- "-w"; then
    base64 -w0 "${PRIV_KEY}"
  else
    base64 "${PRIV_KEY}" | tr -d '\n'
  fi
 
  local SERVER_IP
  SERVER_IP="$(ip -o -4 addr show | awk '!/ lo / && /inet /{gsub(/\/.*/,"",$4); print $4; exit}')"
  echo "[safe] 测试命令：ssh -i ~/.ssh/${KEY_NAME} root@<SERVER>"
  [[ -n "${SERVER_IP:-}" ]] && echo "      当前服务器 IP：${SERVER_IP}"
  echo
  echo "[safe] 已启用：仅允许 root 使用密钥登录。"
  echo "[safe] 若需回退：mv -f ${SSHD_BAK} ${SSHD_MAIN} && systemctl restart ssh"
}





echo "[setup] args: $*"

for arg in "$@"; do
   case "${arg}" in
     tool) KERNEL_TUNE_ONLY=1 ;;
     vhost) vhost; exit 0 ;;
     -h|--help|help) usage; exit 0 ;;
     restart) restart; exit 0 ;;
     status) status; exit 0 ;;
     default) default; exit 0 ;;
     webdav) webdav; exit 0 ;;
     sshkey) sshkey; exit 0 ;;
     remove) remove; exit 0 ;;
     renginx) renginx; exit 0 ;;
     rephp) rephp; exit 0 ;;
     remariadb) remariadb; exit 0 ;;
     wslinit) wslinit; exit 0 ;;
     "") ;;
     *) echo "[setup] 未知参数: ${arg}"; usage; exit 1 ;;
   esac
 done

if [[ "$IS_LAN" -eq 1 ]]; then
    red "[env] 当前为内网环境，将跳过证书申请。"
    read -rp "是否强制申请证书？[y/N] " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ [Yy]$ ]]; then
      green "[env] 已选择强制申请证书。"
      IS_LAN=0
    else
      red "[env] 保持跳过证书申请。"
    fi
  else
    green "[env] 检测到公网环境，可正常申请证书。"
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


wnmp_kernel_tune() {


  local SYSCTL_FILE="${1:-/etc/sysctl.d/99-wnmp.conf}"
  local SECTION_TAG_BEGIN="# ==== wnmp TUNING BEGIN ===="
  local SECTION_TAG_END="# ==== wnmp TUNING END ===="


  install -d "$(dirname "$SYSCTL_FILE")" 2>/dev/null || true
  if [ ! -f "$SYSCTL_FILE" ]; then
    echo "[sysctl] 创建 ${SYSCTL_FILE}"
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

  echo "[sysctl] 已写入优化区块到: $SYSCTL_FILE"


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
    echo "[thp] THP 已关闭并设置为开机生效"
  fi


  modprobe tcp_bbr 2>/dev/null || true


  echo "[sysctl] 正在重新加载内核参数..."
  if [[ "$SYSCTL_FILE" == */sysctl.conf ]]; then
    sysctl -p || true
  else
    SYSTEMD_LOG_LEVEL=info sysctl --system || true
  fi


  cat > /etc/security/limits.conf <<'EOF'
*               soft    nofile           1000000
*               hard    nofile           1000000
EOF
  grep -q "ulimit -SHn 1000000" /etc/profile || echo "ulimit -SHn 1000000" >> /etc/profile
  echo "[limits] nofile=1000000 & /etc/profile 已更新"

  

  echo -e "\033[32m仅内核/网络调优已完成（含 BBR/fq、THP 关闭、limits 设置）\033[0m"
    read -rp "需要重启以确保全部生效，是否现在重启? [Y/n] " yn
    [ -z "${yn:-}" ] && yn="y"
    if [[ "$yn" =~ ^([yY]|[yY][eE][sS])$ ]]; then
      echo "重启中..."
      reboot
    fi
}



if [ "$KERNEL_TUNE_ONLY" -eq 1 ]; then
  echo "[setup] kernel-only mode ON"
  


  if [ "$is_wsl" -eq 1 ]; then
    cat > /etc/security/limits.conf <<'EOF'
*               soft    nofile           1000000
*               hard    nofile           1000000
EOF
  grep -q "ulimit -SHn 1000000" /etc/profile || echo "ulimit -SHn 1000000" >> /etc/profile
  echo "[limits] nofile=1000000 & /etc/profile 已更新"
    echo -e "\033[33m[skip] 检测到 WSL 环境，跳过内核优化 (wnmp_kernel_tune)...\033[0m"
  else
    echo -e "\033[32m[optimize] 执行内核/网络优化...\033[0m"
    wnmp_kernel_tune
  fi
 
  echo -e "${GREEN}仅内核/网络调优已完成${NC}"
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


if ! grep -q '/usr/local/php/bin' /etc/profile; then
  cp /etc/profile /etc/profile.bak
  sed -i '/^# 以下由脚本添加的全局变量$/,+1d' /etc/profile || true
  cat >> /etc/profile << 'EOF'
export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:$PATH"
EOF
  echo -e "${GREEN}已写入 /etc/profile${NC}"

  source /etc/profile
else
  echo -e "${GREEN}已存在全局变量${NC}"
fi

PHP="/usr/local/php/bin/php"
PHPIZE="/usr/local/php/bin/phpize"
PHPCONFIG="/usr/local/php/bin/php-config"
PECL="/usr/local/php/bin/pecl"

pecl_build_from_source() {

  local EXT="$1"; shift || true
  local CONF_OPTS=(
    --with-php-config="$PHPCONFIG"
  )

  /usr/local/php/bin/pecl -d allow_url_fopen=On download "$EXT" || {
    echo "[${EXT}] pecl download 失败，尝试 curl 获取..."
    curl -fL -o "${EXT}.tgz" "https://pecl.php.net/get/${EXT}" || {
      echo "[${EXT}] 获取源码失败"; return 1; }
  }

  local TGZ
  TGZ="$(ls -t ${EXT}-*.tgz | head -n1)"
  [ -n "${TGZ:-}" ] || { echo "[${EXT}] 未找到源码包"; return 1; }
  rm -rf "${TGZ%.tgz}"
  tar xf "$TGZ"
  cd "${TGZ%.tgz}" || { echo "[${EXT}] 进入源码目录失败"; return 1; }

  $PHPIZE
  ./configure "${CONF_OPTS[@]}"

  if command -v JOBS >/dev/null 2>&1; then
    make -j${JOBS}
  else
    make -j1
  fi
  make install
  cd ..
  echo "[${EXT}] 构建完成"
}

if [ -f /root/.pearrc ] || [ -f /usr/local/php/etc/pear.conf ]; then
  echo -e "${RED}检测到旧的 PEAR 配置文件，自动删除以避免 PEAR/PECL 报错...${NC}"
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


echo "请选择PHP版本:"
php_version='0'
select phpselcect in "不安装php" "php8.2" "php8.3" "php8.4" "php8.5" ; do
  case $phpselcect in
    "不安装php") php_version='0'; break ;;
    "php8.2") php_version='8.2.29'; break ;;
    "php8.3") php_version='8.3.28'; break ;;
    "php8.4") php_version='8.4.15'; break ;;
    "php8.5") php_version='8.5.0'; break ;;
    *) echo "无效选项 $REPLY";;
  esac
done

echo "请选择mariadb版本:"
mariadbselcect=''
mariadb_version='0'
select mariadbselcect in "不安装mariadb" "1GB内存10.6" "2GB以上内存10.11"; do
  case $mariadbselcect in
    "不安装mariadb") mariadb_version='0'; break ;;
    "1GB内存10.6") mariadb_version='10.6.24'; break ;;
    "2GB以上内存10.11") mariadb_version='10.11.15'; break ;;
    *) echo "无效选项 $REPLY";;
  esac
done
if [ "$mariadb_version" != "0" ]; then
  read -p "请输入要设置的 MySQL root 密码 [默认: needpasswd]: " MYSQL_PASS
  MYSQL_PASS=${MYSQL_PASS:-needpasswd}
fi
read -rp "是否安装NGINX？(y/n): " choosenginx


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
    log "php-$php_version 已存在"
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
  "--disable-phar"
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

if [[  "$php_version" =~ ^8\.5\. ]]; then
  cat <<'EOF' > /usr/local/php/etc/php.ini
extension=swoole.so
extension=apcu.so
extension=inotify.so
extension=redis.so
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

[apc]
apc.enabled=1
apc.enable_cli=1

EOF

else
    cat <<'EOF' > /usr/local/php/etc/php.ini
extension=swoole.so
extension=apcu.so
extension=inotify.so
extension=redis.so
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

[apc]
apc.enabled=1
apc.enable_cli=1

EOF
fi


  systemctl enable php-fpm
  systemctl start php-fpm
  cd /root



  
curl -o swoole.tar.gz https://github.com/swoole/swoole-src/archive/master.tar.gz -L && \
tar zxvf ./swoole.tar.gz && \
mv swoole-src* swoole-src && \
cd swoole-src && \
phpize && \
./configure --with-php-config=/usr/local/php/bin/php-config \
--enable-openssl  --enable-mysqlnd --enable-swoole-curl --enable-cares --enable-iouring --enable-zstd && \
make && make install
  
  pecl_build_from_source redis || echo -e "${RED}警告：redis 安装失败${NC}"
  pecl_build_from_source inotify || echo -e "${RED}警告：inotify 安装失败${NC}"
  pecl_build_from_source apcu || echo -e "${RED}警告：apcu 安装失败${NC}"
else
  echo '不安装php'
fi


case "$choosenginx" in
  y|Y|yes|YES|Yes)

    cd /root
    mkdir -p /home/passwd
    htpasswd -bc /home/passwd/.default wnmp ${MYSQL_PASS}
    chown -R www:www /home/passwd

    ensure_group mariadb
    ensure_user  mariadb mariadb
    mkdir -p /home/wwwroot/default /home/wwwlogs /home/mariadb
    chown -R www:www /home/wwwroot
    chown -R mariadb:mariadb /home/mariadb

    purge_nginx
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

    
    cat <<'EOF' >  /usr/local/nginx/ssl/default/cert.pem
-----BEGIN CERTIFICATE-----
MIIE8jCCAtqgAwIBAgIUOFMzQ50ECAa1fhmUiTG/eBTO7hswDQYJKoZIhvcNAQEL
BQAwcDELMAkGA1UEBhMCQ04xCzAJBgNVBAgMAkdEMQswCQYDVQQHDAJTWjEVMBMG
A1UECgwMTE9DUFJJTlQgRGV2MRQwEgYDVQQLDAtEZXYgUm9vdCBDQTEaMBgGA1UE
AwwRTE9DUFJJTlQtREVWLVJPT1QwHhcNMjUxMTI5MTk0MTU3WhcNMjcxMTI5MTk0
MTU3WjBcMQswCQYDVQQGEwJDTjELMAkGA1UECAwCR0QxCzAJBgNVBAcMAlNaMREw
DwYDVQQKDAhMT0NQUklOVDEMMAoGA1UECwwDRGV2MRIwEAYDVQQDDAkyLmxvYy5j
b20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCk8GRiCu9vKM0qzRNV
64kp1hZBBTZxtf4s0aL5rc03qVgDQ87wiCqp7VWi6Vk4RNZ5WYBCBRwWhsKExpQ1
Xzbo4CfrPpx7NabPGW6ewujNuD/vPGZcS0WjlatVheC81VN82l6sKW2Uxd3M59V/
iPc89HUnQaitVWazUoXbjrFgm0p/V7ytTE2c39PCxYnor5CzEeVd3rCJkpkOBdz1
szQ5UamTwXLFA1pzEIHPJxnUbno0I6dbEWhYH7r0xfcrL6HVNxAhFEoKJNwUB5Iz
A11amxsxgZILzOUTOKuKPIAj8FaYMv7ivfMOP8V4qN1Lhu1tVyS2oD91HRfN2mS2
z5pVAgMBAAGjgZcwgZQwJQYDVR0RBB4wHIIJMi5sb2MuY29tgglsb2NhbGhvc3SH
BH8AAAEwCQYDVR0TBAIwADALBgNVHQ8EBAMCBaAwEwYDVR0lBAwwCgYIKwYBBQUH
AwEwHQYDVR0OBBYEFMOTdh2o3MAzdxqKoYirQcL/XZbjMB8GA1UdIwQYMBaAFFDQ
WWLS8T3N/rsLu0/W6r1Vj/lwMA0GCSqGSIb3DQEBCwUAA4ICAQB7Zu8MeJDdC9sT
FqRFMrESGVnkzazhIrGKkJ3ZmcIWrt4G8eXnCJiyE4cZIi0gT9gjvdJtv/qKj/DP
Xmi9jkK4DvSkjbz3f5l90Imy2Bn3+vHEOgo17aRmCbm4j+Y5TRxhc8IyBK2aqJrN
tx6+vySJ5CQeU1VPPJAbmdzX5YwPylHihoUB9zrlWN9l0jytYGDW/EUOm/ItUsgo
RVyV/8x+sNokLKrW36sPPBo5JlvfsrxJ06jRvI4HiTK+9SR7ACwKGTm3cPlbRdki
XHtVcKTTjDbudGV4hfCLfhkxEOdj7ABCNtS8AJI90TfKOriE9atD46AY/qLrnGC3
+xy/F6pTchQ171KSDl+4KzM+Xi+GwBZKr1Lx5Je8w0V2pLfvUBkavFI2U7yUHh1/
zMW/80LsVcPjjyyVtGKgJ1BfQcoURO6ko5Xc4NvsM1iWvi+ocmK2n2caaIFR10lO
8Bvs3F5et2HfZ69H7o9r0fu9TVM29GXnkzAg7Xecw1MLTiAbllMe7mZUA1PfAMN0
KT5c7vrRb1EfBKGD5vlwC3qSq7qiOi+QhtpIKctpdvTmjFL4F9u1+rQH3M9vYbgN
Bm4DDPcsiaD4NborIGFRQs2xWBRfngVMRrxVVD7cyA36D4Wi+Hig3YSSWVM8JNRw
6XeH6yuiVt1ABv7Pn1DYOObaaqWLQw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFwTCCA6mgAwIBAgIUXMq/IPbxwuczZiSNt74UOl5qf/kwDQYJKoZIhvcNAQEL
BQAwcDELMAkGA1UEBhMCQ04xCzAJBgNVBAgMAkdEMQswCQYDVQQHDAJTWjEVMBMG
A1UECgwMTE9DUFJJTlQgRGV2MRQwEgYDVQQLDAtEZXYgUm9vdCBDQTEaMBgGA1UE
AwwRTE9DUFJJTlQtREVWLVJPT1QwHhcNMjUxMTIwMTM0NTI5WhcNMzUxMTE4MTM0
NTI5WjBwMQswCQYDVQQGEwJDTjELMAkGA1UECAwCR0QxCzAJBgNVBAcMAlNaMRUw
EwYDVQQKDAxMT0NQUklOVCBEZXYxFDASBgNVBAsMC0RldiBSb290IENBMRowGAYD
VQQDDBFMT0NQUklOVC1ERVYtUk9PVDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
AgoCggIBAK4DUea4g6P8sCzMB6O/6+QWOVMEQ6jc2L+Amh3n2OYVpAWiGDYVA7E/
cfcOLrn1KrjS4n68OMGux6tJcCvy3oq2fSxlBB4TzeKMidjcB53OJP0Zu9sYYEur
tCofE9f+vHALH/VbEv9eVXhKJ2zGsaeKXVHF2zjb5v9K+jaiw/ZF8cA/ND3pcfK7
QNO4Xt3dn07IvMCdlLH1cuNOgdWRrfSAtJrij8C2qlphEEzjTko9TAwxmjLVevWk
jvuWjPWshKY6biiGgPwPfWzDU6y2xzlulVerHuscYSkfS1z0DGY9bfYEC6SU3wsL
qyqNci4aYsJLnejxvvqwoO3EGw0ReTNJNtGPCme2mGLi1KQ4oagivH5a/WoD9T8K
R5/eLT9NOYjpfRo8gq9ntiDh2PL1EcJtnlWau3BCko7wFoJpE8Sw+/JBYT/skdE5
quSZ+NteNjCCWJ4c84J2xU73rE+8UumoOa/sDpTqKFV9ltkX+UQtaXh14LYRI4hK
hc1HKMhTmX+x5MRFplO0sVrzQ1yqzxRyyIHtkQo0/jvrWQ5eotoCBKGdXWi99y/X
LV5nQrCitE1Qu+SMehH0R0oaByHgfB/GXhl6zRSa9M5iCVfqq3DB3V3vyu0Qf/yO
X999hnjmF4VMSyuD38fwtLTbcXHZPbN1JA/srTfcOQGEF0lnD8U5AgMBAAGjUzBR
MB0GA1UdDgQWBBRQ0Fli0vE9zf67C7tP1uq9VY/5cDAfBgNVHSMEGDAWgBRQ0Fli
0vE9zf67C7tP1uq9VY/5cDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA
A4ICAQCHbC4KDuoU92ZuQeTdnjKRHWrsHjoBfEYJ/mXfmFHv6vyr0cXAneKi8QY1
x1Uo15doaR9UmHv/0TVJfkLYE5FkxI8laltzJeM/wDdExArMhpBAipOI6z/uUCk4
iv8eJp8B0bg3/BhzZfDkuIz+rudAf6iqbgRDPgX4v6pOops1jg1N9GMVpA+14N0w
SJ5fEo51f8rTozVIc9lq3ws1ov2pIN6btrTDdnGtO1tny5w7RYeL4dXBImg0j6rG
zPI/E9dq7XsWliqKWg9IJ2eVmXGMtDfGhEsy4QtXnm56HFbcNLQp7K2JRl3WeX8R
Jw1a49KCGiGmnPHo9gZ2GthUuFmls5FId+S3597eZpGg6OxQw86Jyrh4XOpCwKG+
aANwXTSEvu8GBDXqJtQ8fsZ78xE73IQHxBB2znzu9u1U0sXLLP81f1hSdJdV8Z/f
WnQYUy8hG9l0gRWduILfC+nWMJP6qPO9I3qA4vhJgPpmNv2JfGsWN5hgRbczALMH
On1uwcgQHhha4vDh0n7g3BEA5epInBhF/CfPprJJkPzyFu+lBybC+3Mt9Jx/Gq7S
Sal1qWV7phSL79x1Aqw8VrsT70vSnFUHNiOW1ZTFf9s9VzMDEIzOZIWQEGw4HFR5
r+XIc4RJ1R7CEXtLktrSD5/T4WEXsNrApsF8PIMDPPcZVfwBNw==
-----END CERTIFICATE-----

EOF

    cat <<'EOF' >  /usr/local/nginx/ssl/default/key.pem
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCk8GRiCu9vKM0q
zRNV64kp1hZBBTZxtf4s0aL5rc03qVgDQ87wiCqp7VWi6Vk4RNZ5WYBCBRwWhsKE
xpQ1Xzbo4CfrPpx7NabPGW6ewujNuD/vPGZcS0WjlatVheC81VN82l6sKW2Uxd3M
59V/iPc89HUnQaitVWazUoXbjrFgm0p/V7ytTE2c39PCxYnor5CzEeVd3rCJkpkO
Bdz1szQ5UamTwXLFA1pzEIHPJxnUbno0I6dbEWhYH7r0xfcrL6HVNxAhFEoKJNwU
B5IzA11amxsxgZILzOUTOKuKPIAj8FaYMv7ivfMOP8V4qN1Lhu1tVyS2oD91HRfN
2mS2z5pVAgMBAAECggEAGtOFzX5wJ/kPuY+Q6VoS5+I2ogz6KG93GjdfKv3OJr3y
dIF8WxnChVB2gQsz+YIUt2L2XdvdOtALO4jdb9Ap1aF+TKAqgk2dG7T2uCKvtk8/
3Xt06JD45XIr44/lQsFC6sfM5cfNLLPWmdj2cV+dBWXQgiSHOJNEeL5fdXDValvv
VMYE/sPl3oaolAzLCjdWTSIWxW+VcyEGgkp/D2kRdplPh2OiqJGCWHkFWAWfH3l/
TxkeAlNR68DRfxfvPLfs8fajWrWnYE8/U/aA+4uyxTldaiStqC2+NtLv4Ky4gATw
2+UPl6hcEYAnSiKmtE4f9nZqotzDq3z1EIXxUWzz1wKBgQDU83X0EbCsTlf2QnCF
oCAeIZ6qeKCqQoGfxQz+5n0JFFXQQPCaMCvw6YFSai1LNrAr7l4L13DhxENqNUjI
yUgZiptETXO1LJNcBcAzH6KhAOtaq0iIQteVAumK8R3soC2kzf21JXDfenW+du7w
C/Rs06jD98o/o4DKpINmUVN9ewKBgQDGSDzs3dM2xg/l/HuDfh72yjNeEU8KCwtx
TD8ObHVElyEk4kK+tdg6FZvnCNcAzh9c+gImxwfSBl4MdD/vJnqOS1jbhXfWu5HK
A8V9R51ALk8MeTgspiDPVekQD0/rMc/0aaRmApU72VY0+/CLhUoVwlQh0IPG1i/M
w4ACqJj2bwKBgQC71xmXtjcCdoTOu6JnrGxIR92ef5MxPEL8/KNPAV8PsDlV3sKd
L5rDAiZJ3VCgxNe3mKaqiVqQO0BAIkpWmn4X0ZTONge3q188z/HO5rvci2QPcYEk
eNmTHqOFJNUBkfVRJ0cBD8q1xl6wKFbxtYngqP94BU4Ivp/voBgsG9aqmwKBgAuN
7Bb1ejhn5EdHpj7sW4uQDtw9b/iq2hjZE5eYlGDR2bmXgcIxQI9p8PLOnhDK8iLt
4rA1yuvfOR3KrGsYN+4Qz/XC2k/mEEHQZHK/eJdj23FjovVfHOxYGkO4ULTo6zBX
85+KKP4a1R4zTDolI0MPVu29g+BTXOe2wL/m6Tr7AoGBAJSe1vUHZxoqhtTKiom1
ci0jt2AQTmyhlAy1iibI1GN892CaYr34IHRkXcxgC1OEvcYhzM/8LfJV2dcnHf0f
+VasylxmTDk5RE2oUKU6K9deoJgOwhrku24dWflLxWgHNgF4LPB93e1wsTOXA6RI
uZ2qi2VUhh62b6j3YrJFENij
-----END PRIVATE KEY-----

EOF

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
<html lang="zh">
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
    <p>抱歉，您没有权限访问此页面。</p>
    <p style="font-size:0.9rem;opacity:0.7;">nginx</p>
    <p style="font-size:0.9rem;opacity:0.7;">该服务器使用wnmp.org的一键安装包搭建而成。</p>
  </div>
</body>
</html>

EOF

cat <<'EOF' >  /usr/local/nginx/html/404.html
<!DOCTYPE html>
<html lang="zh">
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
    <p>请求的资源无法在此服务器上找到。</p>
    <p style="font-size:0.9rem;opacity:0.7;">nginx</p>
    <p style="font-size:0.9rem;opacity:0.7;">该服务器使用wnmp.org的一键安装包搭建而成。</p>
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


    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2c0f:f248::/32;
    set_real_ip_from 2a06:98c0::/29;
    real_ip_header CF-Connecting-IP;
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

    map $host $is_allowed_host {
        default 0;
         ~^(default\.example\.com)$ 1;
    }

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


    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2c0f:f248::/32;
    set_real_ip_from 2a06:98c0::/29;
    real_ip_header CF-Connecting-IP;
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

        root  /home/wwwroot/default;
        index index.html index.php;

        if ($is_allowed_host = 0) { return 403; }

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
        ssl_session_timeout 10m;
        ssl_session_cache   shared:SSL:20m;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5:!RC4:!3DES;
        ssl_prefer_server_ciphers off;

        autoindex_exact_size off;
        autoindex_localtime on;

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





    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx
    cd ..
    apt-get install -y cron curl socat tar
    systemctl enable --now cron

    curl https://get.acme.sh | sh -s email=1@gmail.com

    bash /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

    
    
    ;;
  n|N|no|NO|No)
    echo "您选择了'否'，跳过nginx安装..."
    ;;
  *)
    echo "无效输入，默认退出..."
    exit 1
    ;;
esac

if [ "$mariadb_version" != "0" ]; then
  purge_mariadb

  cd /root
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
performance_schema=OFF
event_scheduler=OFF
skip-name-resolve
wait_timeout = 28800
character-set-server = utf8mb4
sql-mode = NO_ENGINE_SUBSTITUTION
port        = 3306
socket      = /tmp/mariadb.sock
user        = mariadb
basedir     = /usr/local/mariadb
datadir     = /home/mariadb
log_error   = /home/mariadb/mariadb.err
pid-file    = /home/mariadb/mariadb.pid
skip-external-locking


table_open_cache = 10000
open_files_limit = 65535
max_connections  = 1000
max_connect_errors = 100


key_buffer_size = 64M
max_allowed_packet = 16M


sort_buffer_size = 1M
read_buffer_size = 1M
read_rnd_buffer_size = 512K
myisam_sort_buffer_size = 16M
thread_cache_size = 256

query_cache_type = 0
query_cache_size = 0


innodb_buffer_pool_size = 256M
innodb_buffer_pool_instances = 2
innodb_file_per_table = 1
innodb_log_file_size = 64M
innodb_log_buffer_size = 8M
innodb_flush_log_at_trx_commit = 2
innodb_lock_wait_timeout = 60


innodb_data_home_dir = /home/mariadb
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = /home/mariadb


tmp_table_size = 64M
max_heap_table_size = 64M


explicit_defaults_for_timestamp = true
binlog_format = mixed
server-id = 1
expire_logs_days = 10
default_storage_engine = InnoDB
back_log = 128

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
-- 设置 root@localhost 密码
ALTER USER 'root'@'localhost'
  IDENTIFIED VIA unix_socket
  OR mysql_native_password USING PASSWORD('${MYSQL_PASS}');

-- 删除匿名用户
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

-- 禁止 root 远程登录
DROP USER IF EXISTS 'root'@'%';
DROP USER IF EXISTS 'root'@'127.0.0.1';
DROP USER IF EXISTS 'root'@'::1';

-- 删除 test 数据库及其权限
DROP DATABASE IF EXISTS test;

FLUSH PRIVILEGES;
SQL
  echo -e "\n✅ MariaDB 初始化完成，root 密码：\033[1;32m${MYSQL_PASS}\033[0m"
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
  echo "不安装mariadb"
fi
apt --fix-broken install -y
apt autoremove -y


auto_optimize_services() {
  echo "=================================================="
  echo "        自动优化 WNMP（WebDav / Nginx / PHP-FPM / MariaDB）"
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
    echo "[PHP-FPM] 未检测到配置，跳过"
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
    echo "[MariaDB] 未检测到配置，跳过"
  fi

  systemctl restart nginx 2>/dev/null && echo "[OK] nginx 重启成功" || echo "[WARN] nginx 重启失败或未安装"
  systemctl restart php-fpm 2>/dev/null && echo "[OK] php-fpm 重启成功" || echo "[WARN] php-fpm 重启失败或未安装"
  systemctl restart mariadb 2>/dev/null && echo "[OK] mariadb 重启成功" || echo "[WARN] mariadb 重启失败或未安装"

  echo "================= 优 化 结 果 报 告 ================="
  
  [ -f "$PHP_FPM_CONF" ] && { echo "[PHP-FPM]"; grep -E "pm.max_children|pm.start_servers|pm.min_spare_servers|pm.max_spare_servers|request_slowlog_timeout" "$PHP_FPM_CONF" | sed 's/^[ \t]*//'; echo; }
  [ -f "$MYSQL_CONF" ] && { echo "[MariaDB]"; grep -E "innodb_buffer_pool_size|max_connections|tmp_table_size|max_heap_table_size" "$MYSQL_CONF" | sed 's/^[ \t]*//'; echo; }
  echo "================= 优 化 完 成 ================="
}



auto_optimize_services


if [ "$is_wsl" -eq 1 ]; then
    cat > /etc/security/limits.conf <<'EOF'
*               soft    nofile           1000000
*               hard    nofile           1000000
EOF
  grep -q "ulimit -SHn 1000000" /etc/profile || echo "ulimit -SHn 1000000" >> /etc/profile
  echo "[limits] nofile=1000000 & /etc/profile 已更新"
    echo -e "\033[33m[skip] 检测到 WSL 环境，跳过内核优化 (wnmp_kernel_tune)...\033[0m"
    cd /root
    bash wnmp.sh status
  else
    echo -e "\033[32m[optimize] 执行内核/网络优化...\033[0m"
    wnmp_kernel_tune
  fi
