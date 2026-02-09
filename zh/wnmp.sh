#!/usr/bin/env bash
# WNMP Setup Script
# Copyright (C) 2025 wnmp.org
# Website: https://wnmp.org
# License: GNU General Public License v3.0 (GPLv3)
# Version: 1.39

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
IS_LAN=1
PUBLIC_IP=""
IS_CN=0
PROXY_MODE=${PROXY_MODE:-}
rm -rf /tmp/wnmp_proxy_choice
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
TARGET_PATH="/usr/local/bin/wnmp"

[ -e "${TARGET_PATH}" ] && [ "$(readlink -f "${TARGET_PATH}")" != "${SCRIPT_PATH}" ] && rm -f "${TARGET_PATH}"
[ ! -e "${TARGET_PATH}" ] && cp "${SCRIPT_PATH}" "${TARGET_PATH}" && chmod +x "${TARGET_PATH}"


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
WNMPDIR="/root/sourcewnmp"
mkdir -p "$WNMPDIR"

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
green  " [init] Version: 1.39"
green  "============================================================"
echo
sleep 1

usage() {
  cat <<'USAGE'
用法:
  wnmp               # 正常安装
  wnmp status        # 查看状态
  wnmp sshkey        # ssh密钥登录
  wnmp webdav        # 添加webdav账号
  wnmp vhost         # 创建虚拟主机（含证书）
  wnmp tool          # 仅做内核/网络调优
  wnmp restart       # 重启服务
  wnmp remove        # 卸载
  wnmp renginx       # 卸载nginx
  wnmp rephp         # 卸载php
  wnmp remariadb     # 卸载mariadb
  wnmp fixsshd       # 自检sshd尝试修复
  wnmp devssl        # 自签证书
  wnmp sslcheck      # 安装证书续签脚本
  wnmp ssltest       # 执行ssl检测
  wnmp cf            # 安装cloudflare 真实IP更新任务
  wnmp -h|--help     # 查看帮助
USAGE
}

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

  echo "✅ 服务重启完成"
  exit 0
}
echo "[setup] args: $*"






fixsshd() {
  echo "=========================================="
  echo "[+] 开始修复 SSHD 配置与密钥权限..."
  echo "=========================================="
  set -euo pipefail


  mkdir -p /etc/ssh/sshd_config.d
  chown -R root:root /etc/ssh
  chmod 755 /etc/ssh /etc/ssh/sshd_config.d
  find /etc/ssh/sshd_config.d -type f -exec chown root:root {} \; -exec chmod 0644 {} \;
  echo "[OK] 目录权限已修复。"


  rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub || true
  ssh-keygen -A >/dev/null
  chown root:root /etc/ssh/ssh_host_*_key
  chmod 600 /etc/ssh/ssh_host_*_key
  echo "[OK] SSH HostKey 已重新生成。"


  echo "[*] 检查 sshd 配置是否正常..."
  if ! /usr/sbin/sshd -t; then
    echo "[!] sshd 配置检测失败，输出详细日志："
    /usr/sbin/sshd -t -E /tmp/sshd-check.log || true
    tail -n +1 /tmp/sshd-check.log
    echo "=========================================="
    echo "[X] sshd 配置仍存在错误，请检查上方日志。"
    echo "=========================================="
    return 1
  fi
  echo "[OK] sshd 配置检测通过。"


  systemctl daemon-reload
  systemctl restart ssh || systemctl restart sshd || true
  echo "[OK] sshd 已尝试启动，当前状态："
  systemctl status ssh --no-pager --full || systemctl status sshd --no-pager --full || true
  echo "=========================================="
  echo "[✓] SSH 修复流程完成。"
  echo "=========================================="
}

wslinit() {

  if [ "$(id -u)" -ne 0 ]; then
    echo "[-] 请用 root 或 sudo 运行："
    echo "    sudo bash $0"
    return 1
  fi

  

  echo "[3/7] 更新索引并升级系统..."
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt -y full-upgrade

  echo "[4/7] 安装常用工具和 openssh-server..."
  apt install -y \
    build-essential ca-certificates \
    curl wget unzip git cmake pkg-config \
    htop net-tools iproute2 \
    openssh-server
  update-ca-certificates || true

  echo "[5/7] 配置 SSH（允许 root & 密码登录，可改为更安全策略）..."
  SSHD_CFG="/etc/ssh/sshd_config"
  set_sshd_option() {
    local key="$1" value="$2"
    if grep -qE "^[#[:space:]]*${key}\b" "$SSHD_CFG"; then
      sed -i "s/^[#[:space:]]*${key}.*/${key} ${value}/" "$SSHD_CFG"
    else
      echo "${key} ${value}" >>"$SSHD_CFG"
    fi
  }
  install -d -m 0755 /run/sshd
  ssh-keygen -A

  set_sshd_option "PermitRootLogin" "yes" 
  set_sshd_option "PasswordAuthentication" "yes"
  set_sshd_option "PermitEmptyPasswords" "no"
  set_sshd_option "PubkeyAuthentication" "yes"
  set_sshd_option "UsePAM" "yes"

  echo "[6/7] 启动/重启 SSH 服务..."
  if command -v systemctl >/dev/null 2>&1; then

    systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1; then
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  else
    /usr/sbin/sshd || true
  fi

  echo "[7/7] 设置 root 密码（按提示输入两遍；已设置过可跳过报错无碍）..."
  (passwd root || true)

  echo "[7.1/7] 写入 /etc/wsl.conf（启用 systemd，默认用户 root）..."
  cat >/etc/wsl.conf <<'EOF'
[boot]
systemd=true
[user]
default=root
EOF
  fixsshd || echo "[WARN] sshd 自检失败，请手动执行 wnmp fixsshd 查看原因。"
  echo
  echo "================= 完成 ================="
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
  echo
  echo "  5) 初始化wsl已完成，一定要配合开机自启动脚本，重启一次硬件电脑后才能正常使用"
  echo
  echo "  6) 请重启win11电脑，在linux子系统中再次执行 [wnmp] 才会真实安装web环境"
  echo
  echo "========================================"
  exit 1
}





is_lan() {
    IS_LAN=0
    local ip="" wan="" local_ip=""

    _pick_best_ipv4() {
        local x private=""
     
        local ip_list=""
        if command -v hostname >/dev/null 2>&1; then
            ip_list=$(hostname -I 2>/dev/null)
        fi
        
        if [ -z "$ip_list" ] && command -v ip >/dev/null 2>&1; then
            ip_list=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+')
        fi
        
        
        if [ -z "$ip_list" ] && command -v ifconfig >/dev/null 2>&1; then
            ip_list=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+')
        fi
        
        for x in $ip_list; do
            [[ -z "$x" ]] && continue
            [[ "$x" =~ : ]] && continue
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
        
      
        [[ -n "$private" ]] && echo "$private"
       
        echo ""
    }

   
    _get_public_ipv4() {
        local out=""
        
      
        local api_services=(
            "https://api.ipify.org"
            "https://ifconfig.me/ip" 
            "https://checkip.amazonaws.com"
            "https://icanhazip.com"
        )
        
        
        if command -v curl >/dev/null 2>&1; then
            for api in "${api_services[@]}"; do
                out="$(curl -4fsS --max-time 3 "$api" 2>/dev/null 2>&1 | tr -d '\r\n ')"
                if [[ "$out" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    echo "$out"
                    return 0
                fi
            done
        elif command -v wget >/dev/null 2>&1; then
            for api in "${api_services[@]}"; do
                out="$(wget -4qO- --timeout=3 "$api" 2>/dev/null 2>&1 | tr -d '\r\n ')"
                if [[ "$out" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    echo "$out"
                    return 0
                fi
            done
        fi
        
       
        echo "unknown"
    }

 
    local_ip="$(_pick_best_ipv4)"
    
   
    public_ip="$(_get_public_ipv4)"
    
  
    if [[ -n "$local_ip" ]]; then
    
        if [[ "$local_ip" =~ ^10\. ]] || \
           [[ "$local_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
           [[ "$local_ip" =~ ^192\.168\. ]] || \
           [[ "$local_ip" =~ ^169\.254\. ]]; then
            IS_LAN=1
            PUBLIC_IP="${public_ip:-$local_ip}"
        else
            IS_LAN=0
            PUBLIC_IP="$local_ip"
        fi
    else
       
        IS_LAN=1
        PUBLIC_IP="$public_ip"
    fi
    
   
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="unknown"
    
    echo "$PUBLIC_IP"
    return 0
}

detect_cn_ip() {
  IS_CN=0
  local country=""
  local PUBLIC_IP_LOCAL="${PUBLIC_IP:-}"


  if [[ -z "$PUBLIC_IP_LOCAL" || "$PUBLIC_IP_LOCAL" == "unknown" ]]; then
    return 0
  fi


  is_valid_ipv4() {
    local ip="$1"
    local ipv4_regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    [[ "$ip" =~ $ipv4_regex ]]
  }

  if ! is_valid_ipv4 "$PUBLIC_IP_LOCAL"; then
    return 0
  fi


  local _restore_errexit=0
  case "$-" in *e*) _restore_errexit=1; set +e ;; esac

  _fetch_country() {
    local ip="$1"
    local out=""

    if command -v curl >/dev/null 2>&1; then
     
      local CURL_BASE=(curl -fsS --max-time 3 --connect-timeout 2 --retry 2 --retry-delay 0 --retry-max-time 6)

      out="$("${CURL_BASE[@]}" "https://ipinfo.io/${ip}/country" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

      out="$("${CURL_BASE[@]}" "http://ip-api.com/line/${ip}?fields=countryCode" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

 
      out="$("${CURL_BASE[@]}" "https://ifconfig.co/country-iso?ip=${ip}" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

    
      out="$("${CURL_BASE[@]}" "https://ipwho.is/${ip}" 2>/dev/null \
            | sed -n 's/.*"country_code":"\([^"]*\)".*/\1/p' | head -n1 | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

    elif command -v wget >/dev/null 2>&1; then

      out="$(wget -qO- --timeout=3 --tries=2 "https://ipinfo.io/${ip}/country" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

      out="$(wget -qO- --timeout=3 --tries=2 "http://ip-api.com/line/${ip}?fields=countryCode" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }

      out="$(wget -qO- --timeout=3 --tries=2 "https://ifconfig.co/country-iso?ip=${ip}" 2>/dev/null | tr -d '\r\n ')" || true
      [[ -n "$out" ]] && { echo "$out"; return 0; }
    fi
    if [[ "${IS_CN:-0}" -eq 0 ]]; then
      disable_proxy "127.0.0.1" "32000" >/dev/null 2>&1 || true
      PROXY_MODE="DIRECT"
    fi
    return 1
  }

  country="$(_fetch_country "$PUBLIC_IP_LOCAL")" || true

  [[ $_restore_errexit -eq 1 ]] && set -e


  country="${country^^}" 

  if [[ "$country" == "CN" ]]; then
    IS_CN=1
  fi

  return 0
}

git_clone_wnmp() {
  local repo="$1"
  local dir="${2:-}"

  [[ -z "$repo" ]] && { echo "[git] repo empty"; return 2; }

  local depth=1
  local tries=3
  local timeout_s=120

  local low_speed=128
  local low_time=30
 
  local -a GIT_ENV=()
  if [[ "${PROXY_MODE:-}" == "DIRECT" || "${IS_CN:-0}" -eq 0 ]]; then
    GIT_ENV=(env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy)
  fi

  local repo_norm="${repo%/}"
  local repo_no_git="${repo_norm%.git}"

  local is_github=0 owner_repo=""
  if [[ "$repo_no_git" =~ ^https?://github\.com/([^/]+/[^/]+)$ ]]; then
    is_github=1; owner_repo="${BASH_REMATCH[1]}"
  elif [[ "$repo_no_git" =~ ^git@github\.com:([^/]+/[^/]+)$ ]]; then
    is_github=1; owner_repo="${BASH_REMATCH[1]}"
  fi

  local -a sources=("$repo_norm")
  if [[ $is_github -eq 1 ]]; then
    sources+=(
      "https://ghproxy.com/https://github.com/${owner_repo}.git"
      "https://github.com.cnpmjs.org/${owner_repo}.git"
    )
  fi


  _verify_ok() {
    local target="${1:-}"
    [[ -z "$target" ]] && target="${owner_repo##*/}"
    [[ -d "$target" ]] || return 1

    # 至少要有文件
    [[ -n "$(ls -A "$target" 2>/dev/null)" ]] || return 1

    # 如果是 git clone，必须有 commit
    if [[ -d "$target/.git" ]]; then
      git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
      git -C "$target" rev-list -n 1 HEAD >/dev/null 2>&1 || return 1
    fi

    return 0
  }


  _do_git_clone() {
    local src="$1"
    local target="${dir:-${owner_repo##*/}}"

    rm -rf "$target" 2>/dev/null || true

    if command -v timeout >/dev/null 2>&1; then
      "${GIT_ENV[@]}" timeout "$timeout_s" git \
        -c http.proxy= -c https.proxy= \
        -c http.lowSpeedLimit="$low_speed" \
        -c http.lowSpeedTime="$low_time" \
        -c http.postBuffer=524288000 \
        -c http.followRedirects=true \
        clone --depth="$depth" "$src" ${dir:+ "$dir"}
    else
      "${GIT_ENV[@]}" git \
        -c http.proxy= -c https.proxy= \
        -c http.lowSpeedLimit="$low_speed" \
        -c http.lowSpeedTime="$low_time" \
        -c http.postBuffer=524288000 \
        -c http.followRedirects=true \
        clone --depth="$depth" "$src" ${dir:+ "$dir"}
    fi

    _verify_ok "$target"
  }


  _zip_fallback() {
    [[ $is_github -ne 1 ]] && return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v unzip >/dev/null 2>&1 || return 1

    local target="${dir:-${owner_repo##*/}}"
    rm -rf "$target" 2>/dev/null || true

    local tmpzip tmpdir
    tmpzip="$(mktemp -t wnmp_git.XXXX.zip)"
    tmpdir="$(mktemp -d -t wnmp_git.XXXX)"

    for br in master main; do
      local url="https://codeload.github.com/${owner_repo}/zip/refs/heads/${br}"
      echo "[git] zip fallback: $url"
      if curl -fL --connect-timeout 10 --max-time 180 -o "$tmpzip" "$url"; then
        unzip -q "$tmpzip" -d "$tmpdir" || continue
        local srcdir
        srcdir="$(find "$tmpdir" -maxdepth 1 -type d -name "*-${br}" | head -n1)"
        [[ -z "$srcdir" ]] && continue

        mkdir -p "$target"
        cp -a "$srcdir"/. "$target"/

        rm -rf "$tmpzip" "$tmpdir"
        _verify_ok "$target"
        return $?
      fi
    done

    rm -rf "$tmpzip" "$tmpdir"
    return 1
  }


  local src i
  for src in "${sources[@]}"; do
    for ((i=1; i<=tries; i++)); do
      echo "[git] clone try $i/$tries: $src"
      if _do_git_clone "$src"; then
        echo "[git] success: $src"
        return 0
      fi
      echo "[git] failed, sleep $((i*2))s..."
      sleep $((i*2))
    done
  done

  echo "[git] git clone failed, try zip..."
  if _zip_fallback; then
    echo "[git] zip fallback success"
    return 0
  fi

  echo "[git] all failed: $repo_norm"
  return 1
}



download_with_mirrors() {
  local url="$1"
  local out="$2"
  local label="${3:-download}"
  local ua="Mozilla/5.0"
  local tmp="${out}.part"

  local MAX_ROUNDS=3
  local ROUND_SLEEP=5

  
  local LOCAL_SOCKS_BIND="127.0.0.1"
  local LOCAL_SOCKS_PORT="32000"

  mkdir -p "$(dirname "$out")" 2>/dev/null || true



  _ensure_socks_ready() {
    local retry=3
    while (( retry > 0 )); do
      if proxy_healthcheck 2>/dev/null; then
        return 0
      fi

      echo "[$label][INFO] 尝试启动 SSH 隧道..."
      enable_proxy >/dev/null 2>&1 || true
      sleep 5
      (( retry-- ))
    done

    proxy_healthcheck 2>/dev/null
  }

  
  _curl_force_direct_opts() {
    
    echo "--proxy" "" "--noproxy" "*"
  }


  _curl_proxy_opts() {
    if (( USE_SOCKS == 1 )); then
      echo "--socks5-hostname" "${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}"
    else
      echo
    fi
  }


  _wget_proxy_env_on() {
    export http_proxy="socks5h://${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}"
    export https_proxy="socks5h://${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    export ALL_PROXY="socks5h://${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}"
    export all_proxy="$ALL_PROXY"
    export WGETRC="/dev/null"
  }
  _wget_proxy_env_off() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy WGETRC
  }


  _aria2_proxy_opts() {
    if (( USE_SOCKS == 1 )); then
      printf '%s ' \
        "--all-proxy=socks5h://${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}" \
        "--all-proxy-connect-timeout=10" \
        "--all-proxy-timeout=60"
    fi
  }



  local final_url="$url"

if command -v curl >/dev/null 2>&1; then

  final_url="$(
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
      curl -A "$ua" -fsSLI \
        --proxy "" --noproxy "*" \
        --connect-timeout 10 --max-time 30 \
        -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null \
    || true
  )"

elif command -v wget >/dev/null 2>&1; then
  local loc=""

  loc="$(
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
      wget -S --spider -O /dev/null \
        --timeout=10 --tries=2 \
        --no-proxy \
        "$url" 2>&1 | \
      awk -F': ' '/^  Location: /{print $2}' | tail -n1 | tr -d '\r' \
    || true
  )"
  [[ -n "$loc" ]] && final_url="$loc"
fi

[[ -z "$final_url" ]] && final_url="$url"

 
  local candidates=()
  candidates+=("$final_url" "$url")

  # uniq
  local uniq=() x y seen
  for x in "${candidates[@]}"; do
    [[ -z "$x" ]] && continue
    seen=0
    for y in "${uniq[@]}"; do
      [[ "$y" == "$x" ]] && seen=1 && break
    done
    [[ $seen -eq 0 ]] && uniq+=("$x")
  done
  candidates=("${uniq[@]}")



  local USE_SOCKS=0
  local round try_url ok

  for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo "[$label] ===== Round $round / $MAX_ROUNDS ====="
    rm -f "$tmp"

   
    if [[ "${PROXY_MODE:-}" == "DIRECT" ]]; then
      USE_SOCKS=0
      _wget_proxy_env_off
      echo "[$label][INFO] 已选择直连：强制直连（不使用代理）"

    elif [[ "${IS_CN:-0}" -eq 0 ]]; then
      USE_SOCKS=0
      _wget_proxy_env_off
      echo "[$label][INFO] 非大陆IP：强制直连（不使用代理）"

    else
    
      if _ensure_socks_ready; then
        USE_SOCKS=1
        echo "[$label][INFO] 大陆IP：SSH 隧道可用，使用 socks5 代理下载"
      else
        USE_SOCKS=0
        _wget_proxy_env_off
        echo "[$label][WARN] 大陆IP：SSH 隧道不可用，尝试直连下载"
      fi
    fi

    for try_url in "${candidates[@]}"; do
      echo "[$label] trying: $try_url (socks=$USE_SOCKS)"

      ok=0
      if command -v aria2c >/dev/null 2>&1; then
        if (( USE_SOCKS == 1 )); then
          aria2c -c -x 8 -s 8 -k 1M \
            --connect-timeout=10 --timeout=60 --retry-wait=1 --max-tries=5 \
            --allow-overwrite=true \
            --user-agent="$ua" \
            $(_aria2_proxy_opts) \
            -o "$(basename "$tmp")" -d "$(dirname "$tmp")" \
            "$try_url" && ok=1 || ok=0
        else
    
          aria2c -c -x 8 -s 8 -k 1M \
            --connect-timeout=10 --timeout=60 --retry-wait=1 --max-tries=5 \
            --allow-overwrite=true \
            --user-agent="$ua" \
            --all-proxy="" \
            -o "$(basename "$tmp")" -d "$(dirname "$tmp")" \
            "$try_url" && ok=1 || ok=0
        fi

      elif command -v curl >/dev/null 2>&1; then
        if (( USE_SOCKS == 1 )); then
          curl -A "$ua" -fL --http1.1 \
            --socks5-hostname "${LOCAL_SOCKS_BIND}:${LOCAL_SOCKS_PORT}" \
            --connect-timeout 10 --max-time 900 \
            --retry 5 --retry-delay 1 --retry-connrefused \
            -C - -o "$tmp" "$try_url" && ok=1 || ok=0
        else
     
          env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
            curl -A "$ua" -fL --http1.1 \
            --proxy "" --noproxy "*" \
            --connect-timeout 10 --max-time 900 \
            --retry 5 --retry-delay 1 --retry-connrefused \
            -C - -o "$tmp" "$try_url" && ok=1 || ok=0
        fi

      else
      
        if (( USE_SOCKS == 1 )); then
          _wget_proxy_env_on
        else
          _wget_proxy_env_off
        fi

        wget -c --timeout=10 --tries=5 --waitretry=1 \
          --header="User-Agent: $ua" \
          -O "$tmp" "$try_url" && ok=1 || ok=0
      fi

      if [[ $ok -eq 1 && -s "$tmp" ]]; then
        mv -f "$tmp" "$out"
        echo "[$label][OK] -> $out"
        return 0
      fi
    done

    if (( round < MAX_ROUNDS )); then
      echo "[$label][WARN] round $round failed, retry after ${ROUND_SLEEP}s..."
      sleep "$ROUND_SLEEP"
    fi
  done

  rm -f "$tmp"
  echo "[$label][ERROR] download failed after $MAX_ROUNDS rounds (candidates exhausted)."
  return 1
}


aptinit() {
    local ORIG_IS_CN="${IS_CN:-0}" 
    local APT_USE_CN_MIRROR=0 

    echo "当前IP: $PUBLIC_IP, IS_CN=$IS_CN"

    local MIRROR_CHOICE=""
    local MIRROR_NAME=""
    local UBUNTU_MIRROR=""
    local DEBIAN_MIRROR=""
    local SECURITY_MIRROR=""

   
    if [[ "${IS_CN:-0}" -eq 1 ]]; then
        echo
        echo "检测到大陆 IP，可切换国内 APT 镜像源："
        echo
        echo "  1) 阿里云 (aliyun)"
        echo "  2) 清华大学 (tsinghua)"
        echo "  3) 网易 163"
        echo "  4) 华为云 (huawei)"
        echo "  5) 不切换，保持当前源"
        echo

        if [[ -n "${APT_MIRROR:-}" ]]; then
            MIRROR_CHOICE="$APT_MIRROR"
            echo "使用环境变量指定镜像：$MIRROR_CHOICE"
        else
            read -rp "请选择镜像源 [1-5]，直接回车默认 5: " MIRROR_CHOICE
            MIRROR_CHOICE="${MIRROR_CHOICE:-5}"
        fi

        echo "最终选择的镜像序号：$MIRROR_CHOICE"

        case "$MIRROR_CHOICE" in
            1|aliyun)
                APT_USE_CN_MIRROR=1
                MIRROR_NAME="阿里云"
                UBUNTU_MIRROR="https://mirrors.aliyun.com/ubuntu/"
                DEBIAN_MIRROR="https://mirrors.aliyun.com/debian/"
                SECURITY_MIRROR="https://mirrors.aliyun.com/debian-security/"
                ;;
            2|tsinghua)
                APT_USE_CN_MIRROR=1
                MIRROR_NAME="清华大学"
                UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian/"
                SECURITY_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian-security/"
                ;;
            3|163)
                APT_USE_CN_MIRROR=1
                MIRROR_NAME="网易 163"
                UBUNTU_MIRROR="https://mirrors.163.com/ubuntu/"
                DEBIAN_MIRROR="https://mirrors.163.com/debian/"
                SECURITY_MIRROR="https://mirrors.163.com/debian-security/"
                ;;
            4|huawei)
                APT_USE_CN_MIRROR=1
                MIRROR_NAME="华为云"
                UBUNTU_MIRROR="https://repo.huaweicloud.com/ubuntu/"
                DEBIAN_MIRROR="https://repo.huaweicloud.com/debian/"
                SECURITY_MIRROR="https://repo.huaweicloud.com/debian-security/"
                ;;
            5|keep|"")
                APT_USE_CN_MIRROR=0
                echo "保持当前 APT 源，不进行切换。"
                ;;
            *)
                APT_USE_CN_MIRROR=0
                echo "无效选择，保持当前源。"
                ;;
        esac
    else
        echo "非大陆 IP，使用默认源..."
    fi

   
    if [[ "$APT_USE_CN_MIRROR" -eq 1 ]]; then
        echo
        echo "使用镜像：$MIRROR_NAME"
        echo "检测系统..."

        . /etc/os-release 2>/dev/null || {
            echo "无法读取 /etc/os-release，跳过镜像源设置"
            APT_USE_CN_MIRROR=0
        }
    fi

    if [[ "$APT_USE_CN_MIRROR" -eq 1 ]]; then
        local ID_LOWER
        ID_LOWER="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"
        local CODENAME="${VERSION_CODENAME:-}"

        echo "    ID=${ID_LOWER}, CODENAME=${CODENAME}"
        echo "备份并写入镜像源..."

        [ -f /etc/apt/sources.list ] && \
            cp /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d-%H%M%S)"

        if [ -d /etc/apt/sources.list.d ]; then
            mkdir -p /etc/apt/sources.list.d/backup
            mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/backup/ 2>/dev/null || true
            mv /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/backup/ 2>/dev/null || true
        fi

        if [[ "$ID_LOWER" = "ubuntu" ]]; then
            CODENAME="${CODENAME:-noble}"
            cat >/etc/apt/sources.list <<EOF
deb ${UBUNTU_MIRROR} ${CODENAME} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${CODENAME}-updates main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${CODENAME}-security main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${CODENAME}-backports main restricted universe multiverse
EOF
            echo "Ubuntu 源已切换为：$MIRROR_NAME (${CODENAME})"

        elif [[ "$ID_LOWER" = "debian" ]]; then
            CODENAME="${CODENAME:-trixie}"
            cat >/etc/apt/sources.list <<EOF
deb ${DEBIAN_MIRROR} ${CODENAME} main contrib non-free non-free-firmware
deb ${DEBIAN_MIRROR} ${CODENAME}-updates main contrib non-free non-free-firmware
deb ${SECURITY_MIRROR} ${CODENAME}-security main contrib non-free non-free-firmware
deb ${DEBIAN_MIRROR} ${CODENAME}-backports main contrib non-free non-free-firmware
EOF
            echo "Debian 源已切换为：$MIRROR_NAME (${CODENAME})"
        else
            echo "未识别的发行版：$ID_LOWER，不改源。"
        fi
    fi

    echo
    echo "更新索引并升级系统..."
    export DEBIAN_FRONTEND=noninteractive
    apt update || echo "apt update 失败，继续执行..."
    apt -y full-upgrade || echo "apt upgrade 失败，继续执行..."
    update-ca-certificates 2>/dev/null || true


    IS_CN="$ORIG_IS_CN"
    echo "aptinit 完成"
    return 0
}



enable_proxy() {

  local SSH_USER="wnmp"
  local SSH_PASS="passwdwnmp"
  local SSH_PORT="22"

  local SSH_HOSTS=(
    "51.178.43.90"
    "85.121.48.221"
    "43.134.121.131"
  )

  local LOCAL_BIND="127.0.0.1"
  local LOCAL_PORT="32000"

  local CONNECT_TIMEOUT=10
  local TUNNEL_WAIT=3

  local TUN_LOG="/tmp/wnmp_ssh_socks_tunnel.log"
  local SSHPASS_PATH

  local CHOICE_FILE="/tmp/wnmp_proxy_choice"
  local arg_mode="${1:-}"

  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy

  if ! command -v sshpass >/dev/null 2>&1; then
    
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y sshpass >/dev/null 2>&1 || true
    fi
  fi

  SSHPASS_PATH="$(command -v sshpass)"
  if [[ -z "$SSHPASS_PATH" ]]; then
    
    return 1
  fi

  _port_in_use() {
    if command -v ss >/dev/null 2>&1; then
      ss -lnt | grep -qE "${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)"
    else
      netstat -lnt 2>/dev/null | grep -qE "${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)"
    fi
  }

  _kill_old_tunnel() {
    fuser -k "${LOCAL_BIND}:${LOCAL_PORT}/tcp" 2>/dev/null || true
    pkill -9 -f "ssh.*-D[[:space:]]*${LOCAL_BIND}:${LOCAL_PORT}" 2>/dev/null || true
    pkill -9 -f "sshpass.*ssh.*-D[[:space:]]*${LOCAL_BIND}:${LOCAL_PORT}" 2>/dev/null || true
    sleep 0.3
  }

  _start_tunnel() {
    local host="$1"
    echo "[proxy][INFO] 启动隧道：${host}"

    "$SSHPASS_PATH" -p "$SSH_PASS" ssh \
      -p "$SSH_PORT" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$CONNECT_TIMEOUT" \
      -o ExitOnForwardFailure=yes \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o PasswordAuthentication=yes \
      -o TCPKeepAlive=yes \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=3 \
      -o LogLevel=ERROR \
      -fN \
      -D "${LOCAL_BIND}:${LOCAL_PORT}" \
    "${SSH_USER}@${host}" >>"$TUN_LOG" 2>&1

    local i=0
    while ! _port_in_use && (( i < TUNNEL_WAIT * 10 )); do
      sleep 0.1
      ((i++))
    done

    if _port_in_use; then
   
      if proxy_healthcheck "$LOCAL_BIND" "$LOCAL_PORT" "https://github.com" 6; then
        echo "[proxy][OK] 隧道可用 ${LOCAL_BIND}:${LOCAL_PORT}"
        return 0
      fi

      echo "[proxy][WARN] 端口已监听但探测失败，重启隧道..."
      _kill_old_tunnel
      return 1
    else
      echo "[proxy][ERROR] 隧道启动失败"
      tail -n 30 "$TUN_LOG" 2>/dev/null || true
      return 1
    fi
  }

  _apply_env() {
    local proxy_addr="socks5h://${LOCAL_BIND}:${LOCAL_PORT}"

    export ALL_PROXY="$proxy_addr"
    export all_proxy="$proxy_addr"
    export HTTP_PROXY="$proxy_addr"
    export HTTPS_PROXY="$proxy_addr"
    export http_proxy="$proxy_addr"
    export https_proxy="$proxy_addr"

    git config --global http.proxy "$proxy_addr" >/dev/null 2>&1 || true
    git config --global https.proxy "$proxy_addr" >/dev/null 2>&1 || true

    export NO_PROXY="127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    export no_proxy="$NO_PROXY"

mkdir -p /etc/apt/apt.conf.d
tee /etc/apt/apt.conf.d/99-no-proxy >/dev/null <<EOF
Acquire::http::Proxy "DIRECT";
Acquire::https::Proxy "DIRECT";
Acquire::ftp::Proxy "DIRECT";
Acquire::socks::Proxy "DIRECT";
EOF

    echo "[proxy][OK] 代理已启用：$proxy_addr"
  }

  local choice=""


  if [[ -n "$arg_mode" ]]; then
    choice="$arg_mode"
  elif [[ -n "${WNMP_PROXY_MODE:-}" ]]; then
    choice="${WNMP_PROXY_MODE}"
  elif [[ -s "$CHOICE_FILE" ]]; then
    choice="$(cat "$CHOICE_FILE" 2>/dev/null | tr -d '\r\n ')"
  fi

 
  if [[ -z "$choice" ]]; then
    if [[ -t 0 ]]; then
      while true; do
        echo
        echo "=== 请选择代理模式 ==="
        echo "0) 直连（不使用任何代理）"
        echo "1) 使用代理节点: ${SSH_HOSTS[0]}"
        echo "2) 使用代理节点: ${SSH_HOSTS[1]}"
        echo "3) 使用代理节点: ${SSH_HOSTS[2]}"
        read -rp "请输入选择 (0-3): " choice
        [[ "$choice" =~ ^[0-3]$ ]] && break
        echo "[proxy][WARN] 输入无效，请输入 0-3"
      done
    else
      choice="AUTO"
    fi
  fi

   if [[ "$choice" == "0" || "${choice^^}" == "DIRECT" ]]; then
    echo "[proxy][INFO] Direct connection selected, disabling proxy..."

    _kill_old_tunnel

   
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy || true
    git config --global --unset-all http.proxy  2>/dev/null || true
    git config --global --unset-all https.proxy 2>/dev/null || true
    git config --global --unset-all http.https://github.com.proxy  2>/dev/null || true
    git config --global --unset-all https.https://github.com.proxy 2>/dev/null || true

    PROXY_MODE="DIRECT"
    echo "DIRECT" >"$CHOICE_FILE" 2>/dev/null || true
    echo "[proxy][OK] Direct mode enabled (git/env proxy cleared)"
    return 0
  fi


  local host=""
  case "${choice^^}" in
    1) host="${SSH_HOSTS[0]}" ;;
    2) host="${SSH_HOSTS[1]}" ;;
    3) host="${SSH_HOSTS[2]}" ;;
    AUTO)
     
      ;;
    *)
    
      host="$choice"
      ;;
  esac

  _kill_old_tunnel
  : >"$TUN_LOG" 2>/dev/null || true

  if [[ "${choice^^}" == "AUTO" ]]; then
    local i
    for i in "${!SSH_HOSTS[@]}"; do
      if _start_tunnel "${SSH_HOSTS[$i]}"; then
        host="${SSH_HOSTS[$i]}"
        echo "$((i+1))" >"$CHOICE_FILE" 2>/dev/null || true
        _apply_env
        PROXY_MODE="SOCKS"
        return 0
      fi
    done
    echo "[proxy][ERROR] AUTO: 所有节点均启动失败"
    return 1
  fi

  echo "[proxy][OK] 已选择节点：$host"
  if ! _start_tunnel "$host"; then
    return 1
  fi


  echo "$choice" >"$CHOICE_FILE" 2>/dev/null || true

  _apply_env
  PROXY_MODE="SOCKS"
  return 0
}




disable_proxy() {
   
    set +e
    
    local LOCAL_BIND="${1:-127.0.0.1}"
    local LOCAL_PORT="${2:-32000}"
   
    local SAFE_PORT=$(echo "$LOCAL_PORT" | sed 's/[^0-9]//g')
    local WD_SCRIPT="/tmp/wnmp_socks_watchdog_${SAFE_PORT}.sh"

    local ssh_pattern="ssh[[:space:]]*(-D)[[:space:]]*${LOCAL_BIND}:${SAFE_PORT}([[:space:]]|$)"
    local sshpass_pattern="sshpass[[:space:]]*ssh[[:space:]]*(-D)[[:space:]]*${LOCAL_BIND}:${SAFE_PORT}([[:space:]]|$)"


    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy || true

  
    git config --global --unset-all http.proxy  2>/dev/null || true
    git config --global --unset-all https.proxy 2>/dev/null || true
    git config --global --unset-all http.https://github.com.proxy  2>/dev/null || true
    git config --global --unset-all https.https://github.com.proxy 2>/dev/null || true


    if pgrep -f "$WD_SCRIPT" >/dev/null 2>&1; then
        pkill -TERM -f "$WD_SCRIPT" 2>/dev/null || true
        sleep 0.5
       
        if pgrep -f "$WD_SCRIPT" >/dev/null 2>&1; then
            pkill -9 -f "$WD_SCRIPT" 2>/dev/null || true
        fi
    fi

    pkill -9 -f "wnmp_socks_watchdog.*${LOCAL_BIND}:${SAFE_PORT}\b" 2>/dev/null || true
    rm -f "$WD_SCRIPT" 2>/dev/null || true

   
    pkill -TERM -f "$ssh_pattern" 2>/dev/null || true
    pkill -TERM -f "$sshpass_pattern" 2>/dev/null || true
    sleep 0.5
   
    if pgrep -f "$ssh_pattern" >/dev/null 2>&1; then
        pkill -9 -f "$ssh_pattern" 2>/dev/null || true
    fi
    if pgrep -f "$sshpass_pattern" >/dev/null 2>&1; then
        pkill -9 -f "$sshpass_pattern" 2>/dev/null || true
    fi

   
    if command -v fuser >/dev/null 2>&1; then
        fuser -k -n tcp "${LOCAL_BIND}:${SAFE_PORT}" 2>/dev/null || true
    else
       
        local pid_list
        pid_list=$(ss -lntp 2>/dev/null | grep -E "${LOCAL_BIND}:${SAFE_PORT}\b" | awk -F'[,=]' '{for(i=1;i<=NF;i++){if($i~/pid/){print $(i+1);break}}}' | sed 's/[^0-9]//g')
       
        if [ -n "$pid_list" ]; then
            for pid in $pid_list; do
                kill -TERM "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
            done
        fi
    fi


    sleep 1
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | grep -qE "${LOCAL_BIND}:${SAFE_PORT}\b"; then
            echo "[proxy][WARN] 端口 ${LOCAL_BIND}:${SAFE_PORT} 仍被占用："
            ss -lntp | grep -E "${LOCAL_BIND}:${SAFE_PORT}\b" 2>/dev/null || true
        fi
    fi
mkdir -p /etc/apt/apt.conf.d
tee /etc/apt/apt.conf.d/99-no-proxy >/dev/null <<EOF
Acquire::http::Proxy "DIRECT";
Acquire::https::Proxy "DIRECT";
Acquire::ftp::Proxy "DIRECT";
Acquire::socks::Proxy "DIRECT";
EOF
    set -e
}


proxy_healthcheck() {
  local LOCAL_BIND="${1:-127.0.0.1}"
  local LOCAL_PORT="${2:-32000}"
  local TEST_URL="${3:-https://github.com}"
  local MAX_TIME="${4:-8}"

 
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE "${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)" || return 1
  else
    netstat -lnt 2>/dev/null | grep -qE "${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)" || return 1
  fi


  if ! pgrep -f "ssh( |.* )-D[[:space:]]*${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)" >/dev/null 2>&1 &&
     ! pgrep -f "sshpass( |.* )ssh( |.* )-D[[:space:]]*${LOCAL_BIND}:${LOCAL_PORT}([[:space:]]|$)" >/dev/null 2>&1; then
    return 1
  fi

  curl -fsS \
    --connect-timeout 5 \
    --max-time "$MAX_TIME" \
    --socks5-hostname "${LOCAL_BIND}:${LOCAL_PORT}" \
    "$TEST_URL" >/dev/null 2>&1
}





webdav() {

  local domain="${1:-${domain:-}}"
  local user pass passwd_file ans

  if [[ -z "$domain" ]]; then
    return 1
  fi

  read -rp "是否开启 WebDAV？[y/N] " ans
  ans="${ans:-N}"
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "[webdav] 已跳过。"
    return 0
  fi

  local VHOST_DIR="/usr/local/nginx/vhost"
  local domain_lc conf_path backup
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
    echo "[webdav][ERROR] 未找到 nginx 可执行文件."
    return 1
  fi

  backup="${conf_path}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$conf_path" "$backup" || { echo "[webdav][ERROR] 备份失败：$backup"; return 1; }

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



_wnmp_pick_best_ipv4() {
  local x private="" ip_list=""
  if command -v hostname >/dev/null 2>&1; then
    ip_list="$(hostname -I 2>/dev/null || true)"
  fi
  if [[ -z "$ip_list" ]] && command -v ip >/dev/null 2>&1; then
    ip_list="$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' || true)"
  fi
  for x in $ip_list; do
    [[ -z "$x" ]] && continue
    [[ "$x" =~ ^127\. ]] && continue
    if [[ "$x" =~ ^10\. ]] || [[ "$x" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$x" =~ ^192\.168\. ]] || [[ "$x" =~ ^169\.254\. ]]; then
      [[ -z "$private" ]] && private="$x"
      continue
    fi
    echo "$x"; return 0
  done
  [[ -n "$private" ]] && echo "$private" || echo ""
}

_wnmp_nginx_inject_after_server_name() {
  local conf="$1"
  local snip="$2"
  local tmp_snip tmp_out

  tmp_snip="$(mktemp)"
  tmp_out="$(mktemp)"

  printf "%s\n" "$snip" > "$tmp_snip"

  awk -v SNIPFILE="$tmp_snip" '
    BEGIN { inserted=0 }
    {
      print $0
      if (inserted==0 && $0 ~ /server_name[ \t].*;/) {
        while ((getline line < SNIPFILE) > 0) print line
        close(SNIPFILE)
        inserted=1
      }
    }
  ' "$conf" > "$tmp_out" && mv "$tmp_out" "$conf"

  rm -f "$tmp_snip" "$tmp_out" 2>/dev/null || true
}


_wnmp_nginx_remove_block() {
  local conf="$1" tag="$2"
  sed -i "/^[[:space:]]*# BEGIN ${tag}[[:space:]]*$/,/^[[:space:]]*# END ${tag}[[:space:]]*$/d" "$conf" 2>/dev/null || true
}


_wnmp_nginx_ensure_https_core() {
  local conf="$1"

  if ! grep -qE '^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;[[:space:]]*$' "$conf"; then

    local insert_listens
    insert_listens=$'    listen 80;\n'\
$'    listen 443 ssl;\n'\
$'    listen [::]:443 ssl;\n'\
$'    #listen 443 quic;\n'\
$'    #listen [::]:443 quic;'

    if grep -qE '^[[:space:]]*listen[[:space:]]+80;[[:space:]]*$' "$conf"; then
      sed -i "0,/^[[:space:]]*listen[[:space:]]\\+80;[[:space:]]*$/{
s/^[[:space:]]*listen[[:space:]]\\+80;[[:space:]]*$/${insert_listens}/
}" "$conf"
    else
      sed -i "0,/server[[:space:]]*{/s/server[[:space:]]*{/server{\n${insert_listens}\n/" "$conf"
    fi
  fi

  if ! grep -qE '^[[:space:]]*http2[[:space:]]+on;[[:space:]]*$' "$conf"; then
    _wnmp_nginx_inject_after_server_name "$conf" '    http2 on;'
  fi
  if ! grep -qE '^[[:space:]]*http3[[:space:]]+on;[[:space:]]*$' "$conf"; then
    _wnmp_nginx_inject_after_server_name "$conf" '    #http3 on;'
  fi

  if ! grep -qE '^[[:space:]]*add_header[[:space:]]+Alt-Svc[[:space:]]+' "$conf"; then
    _wnmp_nginx_inject_after_server_name "$conf" '    #add_header Alt-Svc 'h3=\":443\"; ma=86400' always;'
  fi
  if ! grep -qE '^[[:space:]]*add_header[[:space:]]+QUIC-Status[[:space:]]+' "$conf"; then
    _wnmp_nginx_inject_after_server_name "$conf" '   #add_header QUIC-Status \$http3 always;'
  fi
}


_wnmp_nginx_set_ssl_paths_devssl() {
  local conf="$1" ssl_dir="$2" ca="${3:-}"
  local cert="${ssl_dir}/cert.pem"
  local key="${ssl_dir}/key.pem"

  _wnmp_nginx_remove_block "$conf" "WNMP-DEVSSL"

  local block
  block="$(cat <<EOF
# BEGIN WNMP-DEVSSL
    # mkcert self-signed for LAN/dev
    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
EOF
)"

  if [ -n "$ca" ]; then
    block+=$'\n'"    ssl_trusted_certificate ${ca};"
  fi

  block+=$'\n'"    ssl_session_cache   shared:SSL:20m;"
  block+=$'\n'"    ssl_protocols TLSv1.2 TLSv1.3;"
  block+=$'\n'"    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';"
  block+=$'\n'"    ssl_prefer_server_ciphers on;"
  block+=$'\n'"    ssl_session_timeout 10m;"
  block+=$'\n'"    ssl_early_data off;"
  block+=$'\n'"    #quic_retry on;"
  block+=$'\n'"# END WNMP-DEVSSL"

  _wnmp_nginx_inject_after_server_name "$conf" "$block"
}


_wnmp_nginx_set_http_to_https_redirect_devssl() {

  local conf="$1"


  sed -i '/# BEGIN WNMP-DEVSSL-REDIRECT/,/# END WNMP-DEVSSL-REDIRECT/d' "$conf" 2>/dev/null || true

  local block
  block="$(cat <<'EOF'
# BEGIN WNMP-DEVSSL-REDIRECT
    # devssl: force http -> https
    if ($server_port = 80) {
        return 301 https://$host$request_uri;
    }
# END WNMP-DEVSSL-REDIRECT
EOF
)"


  awk -v SNIP="$block" '
    BEGIN{inserted=0}
    {
      print $0
      if (inserted==0 && $0 ~ /server_name[ \t].*;/) {
        print SNIP
        inserted=1
      }
    }
  ' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
}


devssl() {
  echo
  green "============================================================"
  green " [devssl] mkcert 本地/局域网自签证书 + 自动注入 vhost HTTPS"
  green "============================================================"
  echo


  if ! command -v mkcert >/dev/null 2>&1; then
    echo "[devssl] 未检测到 mkcert，开始安装..."
    apt update
    apt install -y libnss3-tools curl ca-certificates
    curl -fsSL "https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64" \
      -o /usr/local/bin/mkcert
    chmod +x /usr/local/bin/mkcert
  fi


  echo "[devssl] 初始化 Root CA（只需一次）..."
  mkcert -install >/dev/null 2>&1 || true

  local CAROOT
  CAROOT="$(mkcert -CAROOT 2>/dev/null || true)"
  if [[ -z "$CAROOT" || ! -f "$CAROOT/rootCA.pem" ]]; then
    red "[devssl][ERROR] 未找到 rootCA.pem（mkcert -CAROOT 失败），请检查 mkcert 是否正常。"
    return 1
  fi


  local DOMAINS=()
  shift || true
  if [[ $# -gt 0 ]]; then
    DOMAINS=("$@")
  else
    read -rp "请输入要用于开发 HTTPS 的域名（可多个，空格分隔，如：a.lan www.a.lan）: " -a DOMAINS
  fi
  [[ ${#DOMAINS[@]} -gt 0 ]] || { red "[devssl] 未输入域名，退出。"; return 1; }


  local LAN_IP
  LAN_IP="$(_wnmp_pick_best_ipv4)"
  local SAN_LIST=("${DOMAINS[@]}" "localhost" "127.0.0.1")
  [[ -n "$LAN_IP" ]] && SAN_LIST+=("$LAN_IP")

  local primary="${DOMAINS[0]}"
  local vhost_dir="/usr/local/nginx/vhost"
  local ssl_dir="/usr/local/nginx/ssl/${primary}"

  mkdir -p "$ssl_dir"
  if [[ -n "$ssl_dir" && "$ssl_dir" != "/" && -d "$ssl_dir" ]]; then
    rm -rf "${ssl_dir:?}/"*
  fi
  cd "$ssl_dir"

  echo
  echo "[devssl] 生成证书（SAN）：${SAN_LIST[*]}"

  mkcert "${SAN_LIST[@]}" >/dev/null

  local certfile keyfile
  certfile="$(ls -1 *.pem 2>/dev/null | grep -v -- '-key\.pem$' | head -n1 || true)"
  keyfile="$(ls -1 *-key.pem 2>/dev/null | head -n1 || true)"

  if [[ -z "$certfile" || -z "$keyfile" ]]; then
    red "[devssl][ERROR] mkcert 输出文件未找到（*.pem / *-key.pem），生成失败。"
    return 1
  fi


  mv -f "$certfile" cert.pem
  mv -f "$keyfile"  key.pem

  cp -f "$CAROOT/rootCA.pem" ca.pem

  echo "[devssl][OK] 证书文件："
  echo "  $ssl_dir/cert.pem"
  echo "  $ssl_dir/key.pem"


  local conf1="$vhost_dir/${primary}.conf"
  local conf2="$vhost_dir/${primary#www.}.conf"
  local conf=""

  if [[ -f "$conf1" ]]; then
    conf="$conf1"
  elif [[ -f "$conf2" ]]; then
    conf="$conf2"
  else
    yellow "[devssl][WARN] 未找到 vhost 配置："
    echo "  $conf1"
    echo "  $conf2"
    echo "[devssl] 你可以先执行：wnmp vhost 创建站点，然后再执行 wnmp devssl 域名..."
  fi

  if [[ -n "$conf" ]]; then
    cp -a "$conf" "${conf}.bak-devssl-$(date +%Y%m%d-%H%M%S)" || true


    _wnmp_nginx_ensure_https_core "$conf"

    _wnmp_nginx_set_ssl_paths_devssl "$conf" "$ssl_dir"

    _wnmp_nginx_set_http_to_https_redirect_devssl "$conf"

    sed -i '/Strict-Transport-Security/d' "$conf" 2>/dev/null || true

    if /usr/local/nginx/sbin/nginx -t; then
      /usr/local/nginx/sbin/nginx -s reload || systemctl reload nginx || true
      green "[devssl][OK] 已注入并重载 nginx：$conf"
    else
      red "[devssl][ERROR] nginx -t 失败，已保留备份：${conf}.bak-devssl-*"
      return 1
    fi
  fi

  echo
  yellow "============================================================"
  yellow " [重要] 让手机/其他电脑信任自签 HTTPS：导入 Root CA"
  yellow "============================================================"
  echo "Root CA 目录：$CAROOT"
  echo "Root CA 文件：$CAROOT/rootCA.pem"
  echo
  echo "导入说明（访问你局域网 HTTPS 的设备都要做一次）："
  echo "  • Android：设置 → 安全 → 加密与凭据/证书 → 从存储安装 → CA 证书 → 选择 rootCA.pem"
  echo "  • iOS：把 rootCA.pem 发到手机 → 安装描述文件 → 设置 → 通用 → 关于本机 → 证书信任设置 → 打开信任"
  echo "  • Windows：导出 rootCA.pem → 改名为rootCA.crt → 双击安装证书 → 选择受信任的根证书颁发机构"
  echo
}

download() {
  local domain="$1"
  local enable_public="${2:-}" 
  local ans

  if [[ -z "$enable_public" ]]; then
    read -rp "是否开启 公开目录？[y/N]（Y=开启，N=关闭） " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      enable_public=1
    else
      enable_public=0
    fi
  else
    [[ "$enable_public" == "1" ]] && enable_public=1 || enable_public=0
  fi

  local VHOST_DIR="/usr/local/nginx/vhost"
  local domain_lc conf_path
  domain_lc="$(echo "$domain" | tr '[:upper:]' '[:lower:]')"
  conf_path="$VHOST_DIR/${domain_lc}.conf"
  if [[ ! -f "$conf_path" && "$domain_lc" =~ ^www\. ]]; then
    conf_path="$VHOST_DIR/${domain_lc#www.}.conf"
  fi
  if [[ ! -f "$conf_path" ]]; then
    echo "[download][ERROR] 未找到配置：$VHOST_DIR/${domain_lc}.conf 或 ${domain_lc#www.}.conf"
    return 1
  fi

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

  if [[ "$enable_public" -eq 1 ]]; then
    sed -i '/^[[:space:]]*include[[:space:]]\+enable-php\.conf;[[:space:]]*$/d' "$conf_path"
    echo "[download] 已移除 include enable-php.conf;（禁止 PHP 执行）"

    insert_once "$conf_path" "include download.conf;"
    echo "[download] 已确保 include download.conf;"
  else
    sed -i '/^[[:space:]]*include[[:space:]]\+download\.conf;[[:space:]]*$/d' "$conf_path"
    echo "[download] 已移除 include download.conf;"

    insert_once "$conf_path" "include enable-php.conf;"
    echo "[download] 已确保 include enable-php.conf;"
  fi

  return 0
}




vhost() {
  is_lan
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

 tmpl=$(cat <<'EOF'
server{
    listen 80;
    server_name example;
    root  /home/wwwroot/default;
    index index.html index.php;
    include block.conf;
    error_page 403 =403 @e403;

    location @e403 {
        root html;
        internal;
        default_type text/html;
        try_files /403.html =403;
    }

    error_page 404 =404 @e404;

    location @e404 {
        root html;
        internal;
        default_type text/html;
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
        add_header Cache-Control "public, max-age=86400, immutable";
    }
    
    location ^~ /.well-known/ { allow all; }
    location ~ /\.(?!well-known) {deny all;}

    access_log off;
}
EOF
)




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
    local cert="${dir}/cert.pem"; local key="${dir}/key.pem";
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
      -e '/^[[:space:]]*ssl_trusted_certificate[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_session_timeout[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_session_cache[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_protocols[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_ciphers[[:space:]]\+/d' \
      -e '/^[[:space:]]*ssl_prefer_server_ciphers[[:space:]]\+/d' \
      "$1"
  }

  local REDIR_WWW_SSL REDIR_PLAIN_SSL REDIR_WWW_NO_SSL
  REDIR_WWW_SSL="$(cat <<EOF
# BEGIN AUTO-HTTPS-REDIRECT
    if (\$scheme != https) {
        return 301 https://www.$primary\$request_uri;
    }
    if (\$host !~* ^www\.) {
        return 301 https://www.\$host\$request_uri;
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


  if /usr/local/nginx/sbin/nginx -t; then
    /usr/local/nginx/sbin/nginx -s reload || systemctl reload nginx
    echo "[vhost] Nginx 已重载。"
  else
    echo "[vhost][ERROR] nginx 配置检查失败。"; return 1
  fi

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
      args=( --issue --server letsencrypt --dns dns_cf -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      CF_Token="$CF_Token_val" "$acme_bin" "${args[@]}" --keylength ec-256 || true
    else
      echo "[vhost][ISSUE] 使用 webroot 为所有域名一次性签发..."
      args=( --issue --server letsencrypt -d "$primary" )
      for d in "${others[@]}"; do args+=( -d "$d" ); done
      args+=( --webroot "$site_root" --keylength ec-256 )
      "$acme_bin" "${args[@]}" || true
    fi

    "$acme_bin" --install-cert -d "$primary" \
      --ecc \
      --key-file       "$ssl_dir/key.pem" \
      --fullchain-file "$ssl_dir/cert.pem" \
      --reloadcmd      "true" || true

    if [[ -s "$ssl_dir/key.pem" && -s "$ssl_dir/cert.pem" ]]; then
      cert_success=1
      echo "[vhost][OK]：$primary -> $ssl_dir"

      tmpl=$(cat <<'EOF'
server{
    listen 80;
    listen 443 ssl;
    listen [::]:443 ssl;
    #listen 443 quic;
    #listen [::]:443 quic;
    http2 on;
    #http3 on;
    server_name example;
    root  /home/wwwroot/default;
    index index.html index.php;
    include block.conf;
    error_page 403 =403 @e403;

    location @e403 {
        root html;
        internal;
        default_type text/html;
        try_files /403.html =403;
    }

    error_page 404  =404 @e404;

    location @e404 {
        root html;
        internal;
        default_type text/html;
        try_files /404.html =404;
    }
    tcp_nopush on;
    tcp_nodelay on;
    include enable-php.conf;

    ssl_certificate     /usr/local/nginx/ssl/default/cert.pem;
    ssl_certificate_key /usr/local/nginx/ssl/default/key.pem;
  
    ssl_session_cache   shared:SSL:20m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 10m;
    ssl_early_data off;
    #quic_retry on;
    #add_header Alt-Svc 'h3=":443"; ma=86400' always;
    #add_header QUIC-Status $http3 always;
   

    location ~* /(low)/                 { deny all; }
    location ~* ^/(upload|uploads)/.*\.php$ { deny all; }
    location ~* .*\.(log|sql|db|back|conf|cli|bak|env)$ { deny all; }
    location ~ /\.                      { deny all; access_log off; log_not_found off; }
    location = /favicon.ico             { access_log off; log_not_found off; expires max; try_files /favicon.ico =204; }
    location = /robots.txt              { allow all; access_log off; log_not_found off; }

    location ~* ^.+\.(apk|css|webp|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|pdf|txt|xml|json|mp4|webm|avi|mp3|zip|rar|tar|gz|xlsx|docx|bin|pcm)$ {
        access_log off;
        expires 1d;
        add_header Cache-Control "public, max-age=86400, immutable";
    }
    
    location ^~ /.well-known/ { allow all; }
    location ~ /\.(?!well-known) {deny all;}

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
    echo "$tmpl" | sed \
    -e "s/server_name[[:space:]]\+example;/${server_name_line//\//\\/}/" \
    -e "s#\(root[[:space:]]\+\)/home/wwwroot/default;#\1${site_root};#g" \
    > "$conf"  
 
      update_ssl_paths_single_dir "$conf" "$ssl_dir"
    else
      echo "[vhost][WARN] 证书签发未成功，将按未申请证书处理。"
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
    download "$primary"
    webdav "$primary"
  else
    echo "[vhost][INFO] 跳过 webdav（因未开启/未成功签发证书）。"
  fi


  mkdir -p /home/wwwlogs

  if grep -qE '^[[:space:]]*access_log[[:space:]]+off;[[:space:]]*$' "$conf"; then
    tac "$conf" | sed "0,/^[[:space:]]*access_log[[:space:]]\\+off;[[:space:]]*$/s//    access_log \/home\/wwwlogs\/${primary}.log main if=\$log_ok;/" | tac > "$conf.tmp" \
      && mv "$conf.tmp" "$conf"
  fi




  
  if /usr/local/nginx/sbin/nginx -t; then
    /usr/local/nginx/sbin/nginx -s reload || systemctl reload nginx
    echo "[vhost] Nginx 已重载。"
  else
    echo "[vhost][ERROR] nginx 配置检查失败。"; return 1
  fi
  echo "[vhost] 完成。"
}



purge_nginx() {

  local _errexit_was_on=0
  if set -o | grep -qE '^errexit[[:space:]]+on$'; then
    _errexit_was_on=1
    set +e
  fi

  echo "Purging NGINX (continue no matter what)..."

  systemctl stop nginx 2>/dev/null
  systemctl disable nginx 2>/dev/null
  service nginx stop 2>/dev/null


  if command -v nginx >/dev/null 2>&1; then
    nginx -s quit 2>/dev/null
    nginx -s stop 2>/dev/null
  fi

  sleep 1


  pkill -9 -x nginx 2>/dev/null
  killall -9 nginx 2>/dev/null


  for p in 80 443; do
    PIDS=$(lsof -t -i :"$p" 2>/dev/null)
    if [ -n "$PIDS" ]; then
      kill -9 $PIDS 2>/dev/null
    fi
  done

  rm -f /etc/systemd/system/nginx.service 2>/dev/null
  systemctl daemon-reload 2>/dev/null

  rm -rf /root/.acme.sh /usr/local/nginx /etc/nginx /var/log/nginx /home/wwwlogs/nginx_error.log \
         /usr/sbin/nginx /usr/bin/nginx  /usr/local/src/nginx-* 2>/dev/null


  if [ "$_errexit_was_on" = "1" ]; then
    set -e
  fi

  return 0
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
         /usr/local/src/php-*

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
           /usr/bin/mysql* /usr/bin/mysqld* /usr/local/src/mariadb-*

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
  purge_nginx || true
  purge_php || true
  purge_mariadb || true
  echo "nginx,php,mariadb已全部清理干净"
  exit 0

}
renginx(){
  purge_nginx || true
  echo "nginx已清理干净"
  exit 0

}

rephp(){
  purge_php || true
  echo "php已清理干净"
  exit 0

}

remariadb(){
  purge_mariadb || true
  echo "mariadb已清理干净"
  exit 0

}

sshkey() {
 
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


local NEW_KEY_TYPE NEW_KEY_B64 NEW_KEY_LINE
NEW_KEY_TYPE=$(awk '{print $1}' "${PUB_KEY}" | tr -d '
' || true)
NEW_KEY_B64=$(awk '{print $2}' "${PUB_KEY}" | tr -d '
' || true)
NEW_KEY_LINE="${NEW_KEY_TYPE} ${NEW_KEY_B64} ${COMMENT}"

if [[ -z "${NEW_KEY_TYPE}" || -z "${NEW_KEY_B64}" ]]; then
  echo "[safe][ERROR] 无法解析生成的公钥，请检查 ${PUB_KEY} 内容。"
  return 1
fi

if [[ -f "${AUTH_KEYS}" ]]; then
  cp -a "${AUTH_KEYS}" "${AUTH_KEYS}.bak-${NOW}"
  echo "[safe] 已备份原始授权文件为 ${AUTH_KEYS}.bak-${NOW}"
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

echo "[safe] 授权文件已更新：仅保留最新生成的公钥（${AUTH_KEYS}）。旧公钥已备份到 ${AUTH_KEYS}.bak-${NOW} 。"

find "${SSH_DIR}" -maxdepth 1 -type f \( -name "${KEY_NAME}.bak-*" -o -name "${KEY_NAME}.pub.bak-*" -o -name "${KEY_NAME}.pub.bak-*" \) -print -exec rm -f {} \; || true

find "${SSH_DIR}" -maxdepth 1 -type f -name "${KEY_NAME}.*.bak-*" -print -exec rm -f {} \; || true

echo "[safe] 已删除本目录下历史私钥/公钥备份（如果存在）。"

chmod 700 "${SSH_DIR}"
chmod 600 "${PRIV_KEY}"
chmod 644 "${PUB_KEY}" 
chown root:root "${PRIV_KEY}" "${PUB_KEY}"


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
AllowUsers root wnmp
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
  echo "====================================================================="
  echo "✅ 已成功启用 root 用户【仅允许密钥登录】"
  echo
  echo "🔐 重要提醒：请【不要】复制 / 粘贴私钥内容。"
  echo "🔐 私钥必须以【文件方式】传输，否则极易损坏并导致无法登录。"
  echo
  echo "➡️  推荐方式：使用 SCP 下载私钥文件："
  echo
  echo "   scp -P <SSH端口> root@<服务器IP>:/root/.ssh/${KEY_NAME} ~/.ssh/${KEY_NAME}"
  echo
  echo "   下载完成后请设置权限："
  echo "   chmod 600 ~/.ssh/${KEY_NAME}"
  echo
  echo "➡️  或使用 SFTP 工具下载（WinSCP / FileZilla / Xshell 文件传输）。"
  echo
  echo "====================================================================="
  echo
 
 
  local SERVER_IP
  SERVER_IP="$(ip -o -4 addr show | awk '!/ lo / && /inet /{gsub(/\/.*/,"",$4); print $4; exit}')"
  echo "[safe] 测试命令：ssh -i ~/.ssh/${KEY_NAME} root@<SERVER>"
  [[ -n "${SERVER_IP:-}" ]] && echo "      当前服务器 IP：${SERVER_IP}"
  echo
  echo "[safe] 已启用：仅允许 root 使用密钥登录。"
  echo "[safe] 若需回退：mv -f ${SSHD_BAK} ${SSHD_MAIN} && systemctl restart ssh"

  echo
  echo "⚠️  高级选项（不推荐）"
  echo "⚠️  仅在【无法使用 SCP / SFTP 下载私钥文件】的情况下使用"
  echo "⚠️  复制 / 粘贴私钥内容极易因换行、编码、隐藏字符导致密钥损坏"
  echo
  read -rp "是否仍要以 字符串 形式导出私钥？（仅限高级用户）[y/N]: " export_string </dev/tty

  if [[ "${export_string,,}" =~ ^(y|yes)$ ]]; then
    echo
    cat "${PRIV_KEY}"
    echo
    echo "⚠️  注意：请勿使用记事本等会自动转换换行/编码的编辑器保存私钥文件"
  fi

}




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

if grep -qi "microsoft" /proc/version 2>/dev/null; then

  ssh_running=0

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
      ssh_running=1
    fi
  fi


  if [[ $ssh_running -eq 0 ]]; then
    if pgrep -x sshd >/dev/null 2>&1; then
      ssh_running=1
    fi
  fi

  if [[ $ssh_running -eq 0 ]]; then
    is_lan
    detect_cn_ip || true
    wslinit
  fi

fi


install_mroonga() {
  
  local _err=0
  local mariadb_version PLUGINDIR SRC_SO DST_SO TMP_SO
  local GROONGA_TAR="$WNMPDIR/groonga.tar.gz"
  local MROONGA_TAR="$WNMPDIR/mroonga.tar.gz"
  local GROONGA_SRC="$WNMPDIR/groonga"
  local GROONGA_BUILD="$WNMPDIR/groonga_build"
  local MROONGA_SRC="$WNMPDIR/mroonga"
  local MROONGA_BUILD="$WNMPDIR/mroonga_build"
  local MYCNF="/etc/my.cnf"

  echo "[mroonga] WNMPDIR=$WNMPDIR"

  cd "$WNMPDIR" || { echo "[mroonga][ERROR] cd $WNMPDIR failed"; return 1; }

  echo "[mroonga] purge old groonga packages..."
  apt remove --purge -y 'groonga*' 'libgroonga*' || true
  apt -f install -y || true
  apt autoremove -y || true
  apt clean || true
  rm -rf "$GROONGA_BUILD"
  echo "[mroonga] remove old /usr/local groonga/mroonga..."
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
  ldconfig || true

  echo "[mroonga] install build deps..."
  apt-get update -y || true

  apt-get install -y \
    build-essential cmake ninja-build pkg-config \
    liblz4-dev libzstd-dev libxxhash-dev \
    libevent-dev libpcre2-dev libonig-dev libmsgpack-dev \
    libmecab-dev mecab-ipadic-utf8 \
    libssl-dev zlib1g-dev || { echo "[mroonga][ERROR] build deps install failed"; return 1; }

  cd "$WNMPDIR" || return 1

  echo "[mroonga] fetch groonga source..."
  if [ ! -f "$GROONGA_TAR" ]; then
    rm -rf "$GROONGA_SRC"
    download_with_mirrors "https://packages.groonga.org/source/groonga/groonga-latest.tar.gz" "$GROONGA_TAR" || {
      echo "[mroonga][ERROR] groonga download failed"; return 1; }
    mkdir -p "$GROONGA_SRC"
  else
    mkdir -p "$GROONGA_SRC"
  fi

  echo "[mroonga] extract groonga..."
  rm -rf "$GROONGA_SRC"/*
  tar -zxvf "$GROONGA_TAR" --strip-components=1 -C "$GROONGA_SRC" || {
    echo "[mroonga][ERROR] groonga extract failed"; return 1; }

  echo "[mroonga] build & install groonga..."
  cd "$GROONGA_SRC" || return 1
  rm -rf "$GROONGA_BUILD"
  cmake -S . -B "$GROONGA_BUILD" -G Ninja \
    -DGRN_WITH_MRUBY=OFF \
    -DGRN_WITH_APACHE_ARROW=OFF \
    --preset=release-maximum || { echo "[mroonga][ERROR] groonga cmake failed"; return 1; }

  cmake --build "$GROONGA_BUILD" -j"$(nproc)" || { echo "[mroonga][ERROR] groonga build failed"; return 1; }
  cmake --install "$GROONGA_BUILD" || { echo "[mroonga][ERROR] groonga install failed"; return 1; }
  ldconfig || true

  if command -v groonga >/dev/null 2>&1; then
    groonga --version || true
  else
    echo "[mroonga][WARN] groonga binary not found in PATH (maybe /usr/local/bin not in PATH)"
  fi

  cd "$WNMPDIR" || return 1

  echo "[mroonga] install groonga extra packages..."
 
  apt install -y groonga-token-filter-stem groonga-tokenizer-mecab libgroonga-dev groonga-normalizer-mysql || {
    echo "[mroonga][WARN] apt groonga extra packages install failed (continue)"; }

  echo "[mroonga] fetch mroonga source..."
  if [ ! -f "$MROONGA_TAR" ]; then
    rm -rf "$MROONGA_SRC"
    download_with_mirrors "https://packages.groonga.org/source/mroonga/mroonga-latest.tar.gz" "$MROONGA_TAR" || {
      echo "[mroonga][ERROR] mroonga download failed"; return 1; }
    mkdir -p "$MROONGA_SRC"
  else
    mkdir -p "$MROONGA_SRC"
  fi

  echo "[mroonga] extract mroonga..."
  rm -rf "$MROONGA_SRC"/*
  tar -zxvf "$MROONGA_TAR" --strip-components=1 -C "$MROONGA_SRC" || {
    echo "[mroonga][ERROR] mroonga extract failed"; return 1; }

  echo "[mroonga] build & install mroonga..."
  cd "$MROONGA_SRC" || return 1

  mariadb_version=$(/usr/local/mariadb/bin/mysql_config --version 2>/dev/null)
  if [ -z "$mariadb_version" ]; then
    echo "[mroonga][ERROR] cannot get mariadb version by /usr/local/mariadb/bin/mysql_config"
    return 1
  fi

  local GRN_LIB="/usr/lib/x86_64-linux-gnu/libgroonga.so"
  if [ ! -e "$GRN_LIB" ]; then
    GRN_LIB="/usr/local/lib/libgroonga.so"
  fi
  if [ ! -e "$GRN_LIB" ]; then
    echo "[mroonga][ERROR] libgroonga.so not found in /usr/lib or /usr/local/lib"
    return 1
  fi

  rm -rf "$MROONGA_BUILD"
  cmake \
    -S . \
    -B "$MROONGA_BUILD" \
    -GNinja \
    -DGRN_LIBRARIES="$GRN_LIB" \
    -DMRN_DEFAULT_TOKENIZER=TokenBigramSplitSymbolAlphaDigit \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/mroonga \
    -DMYSQL_BUILD_DIR="$WNMPDIR/mariadb-$mariadb_version/build" \
    -DMYSQL_CONFIG=/usr/local/mariadb/bin/mysql_config \
    -DMYSQL_SOURCE_DIR="$WNMPDIR/mariadb-$mariadb_version" || {
      echo "[mroonga][ERROR] mroonga cmake failed"; return 1; }

  cmake --build "$MROONGA_BUILD" -j"$(nproc)" || { echo "[mroonga][ERROR] mroonga build failed"; return 1; }
  cmake --install "$MROONGA_BUILD" || { echo "[mroonga][ERROR] mroonga install failed"; return 1; }

  echo "[mroonga] run install.sql..."
  /usr/local/mariadb/bin/mysql -u root < /usr/local/mroonga/share/mroonga/install.sql || {
    echo "[mroonga][WARN] install.sql failed (continue to force-install plugin)"; }

  echo "[mroonga] install ha_mroonga.so into MariaDB plugin_dir (atomic)..."
  PLUGINDIR=$(/usr/local/mariadb/bin/mysql_config --plugindir 2>/dev/null)
  
  SRC_SO="$MROONGA_BUILD/ha_mroonga.so"

  if [ ! -s "$SRC_SO" ]; then
    SRC_SO="$(find $MROONGA_BUILD -name ha_mroonga.so -type f -size +10k 2>/dev/null | head -n 1)"
  fi
  if [ ! -s "${SRC_SO:-}" ]; then
    echo "[mroonga][ERROR] built ha_mroonga.so not found under $MROONGA_BUILD"
    return 1
  fi

  DST_SO="$PLUGINDIR/ha_mroonga.so"
  TMP_SO="$DST_SO.tmp.$$"
  cp -f "$SRC_SO" "$TMP_SO" || { echo "[mroonga][ERROR] copy temp ha_mroonga.so failed"; return 1; }
  sync || true
  mv -f "$TMP_SO" "$DST_SO" || { echo "[mroonga][ERROR] move ha_mroonga.so failed"; return 1; }
  chmod 644 "$DST_SO" || true

  echo "[mroonga] ensure ldconfig paths..."
  cat >/etc/ld.so.conf.d/groonga.conf <<'EOF'
/usr/lib/x86_64-linux-gnu
/usr/local/lib
EOF
  ldconfig || true
  systemctl restart mariadb || true
  cd "$WNMPDIR" || true

  echo "[mroonga] cleanup groonga/apache-arrow apt sources..."
  rm -f /etc/apt/sources.list.d/apache-arrow*.list /etc/apt/sources.list.d/apache-arrow*.sources
  rm -f /etc/apt/sources.list.d/groonga*.list /etc/apt/sources.list.d/groonga*.sources
  rm -f /usr/share/keyrings/apache-arrow-archive-keyring.gpg
  rm -f /usr/share/keyrings/groonga-archive-keyring.gpg
  rm -f /etc/apt/trusted.gpg.d/apache-arrow*.gpg /etc/apt/trusted.gpg.d/groonga*.gpg
  rm -f /etc/apt/preferences.d/groonga.pref
  apt-get update || true

  echo "[mroonga][OK] install_mroonga finished."
  return 0
}




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
kernel.core_pattern = core
kernel.core_uses_pid = 1
kernel.sysrq = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_regular = 2
fs.protected_fifos = 1
vm.max_map_count = 1048576
vm.swappiness = 10
kernel.pid_max = 4194304
fs.file-max = 2000000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_tw_reuse = 0
net.ipv4.tcp_max_tw_buckets = 200000
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.promote_secondaries = 1
net.ipv4.conf.all.promote_secondaries = 1
net.ipv4.ping_group_range = 0 2147483647

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

  wnmp_limits_tune 1048576 65535

  echo -e "\033[32m内核/网络调优已完成（含 BBR/fq、THP 关闭、limits 设置）\033[0m"
    read -rp "需要重启以确保全部生效（WSL需要重启Win11电脑），是否现在重启? [Y/n] " yn
    [ -z "${yn:-}" ] && yn="y"
    if [[ "$yn" =~ ^([yY]|[yY][eE][sS])$ ]]; then
      echo "重启中..."
      reboot
    fi
}



tool(){
  echo "[setup] kernel-only mode ON"
  
  wnmp_kernel_tune
 
  echo -e "${GREEN}仅内核/网络调优已完成${NC}"
  exit 0
}



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

cf() {
  set -e

  local OUT="/usr/local/nginx/cloudflare-ips.conf"
  local BIN="/usr/local/bin/wnmp_cf"
  local CRON_MARK="# wnmp:cloudflare-realip"
  local CRON_LINE="17 0 * * * /usr/local/bin/wnmp_cf >/dev/null 2>&1 ${CRON_MARK}"

  echo "[wnmp_cf] Installing/updating ${BIN} ..."

  install -d -m 755 /usr/local/bin /usr/local/nginx
  cat > "${BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OUT="/usr/local/nginx/cloudflare-ips.conf"
LOCK="/var/lock/wnmp_cf.lock"

exec 9>"$LOCK"
flock -n 9 || exit 0

TMP="$(mktemp)"
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT

{
  echo "# Cloudflare IP ranges - auto generated"
  curl -fsSL https://www.cloudflare.com/ips-v4 | sed 's/^/set_real_ip_from /; s/$/;/'
  curl -fsSL https://www.cloudflare.com/ips-v6 | sed 's/^/set_real_ip_from /; s/$/;/'
} > "$TMP"

if ! cmp -s "$TMP" "$OUT"; then
  install -m 644 "$TMP" "$OUT"
  systemctl reload nginx
fi
EOF
  chmod +x "${BIN}"
  echo "[wnmp_cf] Ensuring crontab entry (daily 00:17) ..."
  local tmpcron
  tmpcron="$(mktemp)"

  ( crontab -l 2>/dev/null || true ) \
    | grep -vF "${CRON_MARK}" \
    > "$tmpcron"
  echo "${CRON_LINE}" >> "$tmpcron"
  crontab "$tmpcron"
  rm -f "$tmpcron"

}

wnmp_sslcheck() {
    local ACME_HOME="/root/.acme.sh"
    local SSL_CHECK="$ACME_HOME/sslcheck"
    local CRON_LINE="17 3 * * * $SSL_CHECK >/var/log/sslcheck.log 2>&1"
    local tmp

    echo "[WNMP] sslcheck: begin"

    mkdir -p "$ACME_HOME" || { echo "[WNMP] sslcheck: mkdir failed"; return 1; }


    echo "[WNMP] sslcheck: write $SSL_CHECK"
    cat > "$SSL_CHECK" <<'EOF'
#!/bin/bash
set -u

dir_path="/root/.acme.sh"
acme_bin="/root/.acme.sh/acme.sh"

THRESH_IP_DAYS=1
THRESH_DOMAIN_DAYS=1

SSL_BASE="/usr/local/nginx/ssl"
IP_SSL_DIR="$SSL_BASE/default"


PREFER_LOCAL_CERT=1

USE_ALPN_FOR_IP=0

FLAG="/tmp/acme_renew_need_restart_nginx.flag"
rm -f "$FLAG"

log() { echo -e "[$(date '+%F %T')] $*"; }

is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

nginx_stop_if_running() {
  if systemctl is-active --quiet nginx; then
    log "🛑 Stopping nginx..."
    systemctl stop nginx
  fi
}

nginx_start_if_not_running() {
  if ! systemctl is-active --quiet nginx; then
    log "🚀 Starting nginx..."
    systemctl start nginx
  fi
}


get_end_time_from_file() {
  local cert_file="$1"
  [ -s "$cert_file" ] || return 1
  openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | awk -F= '{print $2}'
}


get_end_time_remote() {
  local host="$1"
  local connect_host="$host"
  
  if [ "${PREFER_LOCAL_CERT:-0}" -eq 1 ]; then
    :
  fi

  if is_ip "$host"; then
    timeout 5 bash -c "echo | openssl s_client -connect '$connect_host:443' 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null" | awk -F= '{print $2}'
  else
    timeout 5 bash -c "echo | openssl s_client -servername '$host' -connect '$connect_host:443' 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null" | awk -F= '{print $2}'
  fi
}

days_left_from_endtime() {
  local end_time="$1"
  local end_ts now_ts
  end_ts=$(date -d "$end_time" +%s 2>/dev/null || true)
  [ -z "${end_ts:-}" ] && return 1
  now_ts=$(date -u +%s)
  echo $(( (end_ts - now_ts) / 86400 ))
}

install_cert_to_dir() {
  local domain="$1"
  local ssl_dir="$2"

  mkdir -p "$ssl_dir"

  log "📥 Installing cert to: $ssl_dir"
  "$acme_bin" --install-cert -d "$domain" \
    --ecc \
    --key-file       "$ssl_dir/key.pem" \
    --fullchain-file "$ssl_dir/cert.pem" \
    --reloadcmd      "true" || true

  if [ -s "$ssl_dir/key.pem" ] && [ -s "$ssl_dir/cert.pem" ]; then
    touch "$FLAG"
    log "✅ Installed OK: $domain"
    return 0
  fi

  log "❌ Install failed (files missing): $domain"
  return 1
}

log "🔎 Scanning acme.sh ECC dirs under: $dir_path"
found_any=0

while IFS= read -r -d '' full; do
  found_any=1
  dir="$(basename "$full")"
  primary="${dir%_ecc}"

  log ""
  log "=============================="
  log "📌 Target: $primary"

  end_time=""

  if [ "${PREFER_LOCAL_CERT:-0}" -eq 1 ]; then

    if is_ip "$primary"; then
      end_time="$(get_end_time_from_file "$IP_SSL_DIR/cert.pem" || true)"
      [ -n "$end_time" ] || log "⚠️ Local cert not found: $IP_SSL_DIR/cert.pem"
    else
      
      end_time="$(get_end_time_from_file "$SSL_BASE/$primary/cert.pem" || true)"
      [ -n "$end_time" ] || log "⚠️ Local cert not found: $SSL_BASE/$primary/cert.pem"
    fi
  fi


  if [ -z "${end_time:-}" ]; then
    end_time="$(get_end_time_remote "$primary" || true)"
    [ -n "$end_time" ] || log "⚠️ Remote probe failed for $primary"
  fi

  if [ -z "${end_time:-}" ]; then
    log "⏭️ Skip: cannot get end date for $primary"
    continue
  fi

  left_days="$(days_left_from_endtime "$end_time" || true)"
  if [ -z "${left_days:-}" ]; then
    log "⏭️ Skip: cannot parse end date: $end_time"
    continue
  fi

  log "  📅 Expiration Date: $end_time"
  log "  ⏳ Days remaining: $left_days"

  if is_ip "$primary"; then
    if [ "$left_days" -lt "$THRESH_IP_DAYS" ]; then
      log "🔁 IP cert needs renew (threshold=$THRESH_IP_DAYS)"
      nginx_stop_if_running

      issue_ok=0
      if [ "${USE_ALPN_FOR_IP:-0}" -eq 1 ]; then
        log "🌐 Issue via ALPN(443): $primary"
        if "$acme_bin" --issue --server letsencrypt -d "$primary" \
            --certificate-profile shortlived --alpn \
            --keylength ec-256 --force; then
          issue_ok=1
        fi
      else
        log "🌐 Issue via standalone(80): $primary"
        if "$acme_bin" --issue --server letsencrypt -d "$primary" \
            --certificate-profile shortlived --standalone \
            --keylength ec-256 --force; then
          issue_ok=1
        fi
      fi

      nginx_start_if_not_running

      if [ "$issue_ok" -eq 1 ]; then
        install_cert_to_dir "$primary" "$IP_SSL_DIR"
      fi
    fi
  else
    if [ "$left_days" -lt "$THRESH_DOMAIN_DAYS" ]; then
      log "🔁 Domain cert needs renew (threshold=$THRESH_DOMAIN_DAYS): $primary"
      if "$acme_bin" --renew -d "$primary" --ecc --force; then
        ssl_dir="$SSL_BASE/$primary"
        install_cert_to_dir "$primary" "$ssl_dir"
      else
        log "❌ Renew failed: $primary"
      fi
    fi
  fi

done < <(find "$dir_path" -maxdepth 1 -type d -name "*_ecc" -print0)

if [ "$found_any" -eq 0 ]; then
  log "⚠️ No *_ecc directories found under $dir_path"
fi

if [ -f "$FLAG" ]; then
  log "♻️ Restart nginx due to cert updates..."
  systemctl restart nginx
  rm -f "$FLAG"
  log "✅ nginx restarted."
else
  log "ℹ️ No cert installed. nginx restart not needed."
fi


EOF
    chmod +x "$SSL_CHECK" || { echo "[WNMP] sslcheck: chmod failed"; return 1; }


    echo "[WNMP] sslcheck: read crontab"
    tmp="$(mktemp)" || { echo "[WNMP] sslcheck: mktemp failed"; return 1; }

    if crontab -l >"$tmp" 2>/dev/null; then
        echo "[WNMP] sslcheck: crontab loaded"
    else
        echo "[WNMP] sslcheck: no existing crontab (ok)"
        : > "$tmp"
    fi


    echo "[WNMP] sslcheck: remove acme.sh cron lines"
    {
 
        awk '!($0 ~ /acme\.sh/ && $0 ~ /--cron/)' "$tmp" > "${tmp}.new"
        mv -f "${tmp}.new" "$tmp"
    } || {
        echo "[WNMP] sslcheck: filter cron failed"
        rm -f "$tmp" "${tmp}.new"
        return 1
    }

 
    echo "[WNMP] sslcheck: ensure sslcheck cron line"
    if ! grep -Fq "$SSL_CHECK" "$tmp" 2>/dev/null; then
        echo "$CRON_LINE" >> "$tmp"
        echo "[WNMP] sslcheck: cron line added"
    else
        echo "[WNMP] sslcheck: cron line already exists"
    fi


    echo "[WNMP] sslcheck: install crontab"
    if crontab "$tmp"; then
        echo "[WNMP] sslcheck: crontab installed"
    else
        echo "[WNMP] sslcheck: crontab install failed"
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"

    echo "[WNMP] sslcheck 已启用：每日执行一次"
    return 0
}

wnmp_ssltest() {
  local dir_path="/root/.acme.sh"
  local SSL_BASE="/usr/local/nginx/ssl"
  local IP_SSL_DIR="$SSL_BASE/default"


  local PREFER_LOCAL_CERT=1

  is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }


  get_end_time_from_file() {
    local cert_file="$1"
    [ -s "$cert_file" ] || return 1
    openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | awk -F= '{print $2}'
  }


  get_cert_end_time_remote() {
    local host="$1"
    if is_ip "$host"; then
      echo | timeout 5 openssl s_client -connect "$host:443" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | awk -F= '{print $2}'
    else
      echo | timeout 5 openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | awk -F= '{print $2}'
    fi
  }

  days_left_from_endtime() {
    local end_time="$1"
    local end_ts now_ts
    end_ts=$(date -d "$end_time" +%s 2>/dev/null || true)
    [ -z "${end_ts:-}" ] && return 1
    now_ts=$(date -u +%s)
    echo $(( (end_ts - now_ts) / 86400 ))
  }

  printf "\n%-30s %-10s %-8s %-12s %-24s\n" "DOMAIN / IP" "TYPE" "SRC" "LEFT(days)" "EXPIRE AT"
  printf "%-30s %-10s %-8s %-12s %-24s\n" "------------------------------" "----------" "--------" "------------" "------------------------"

  while IFS= read -r -d '' full; do
    local dir primary end_time left_days type src cert_file
    dir="$(basename "$full")"
    primary="${dir%_ecc}"

    if is_ip "$primary"; then
      type="IP(short)"
      cert_file="$IP_SSL_DIR/cert.pem"
    else
      type="ECC"
      cert_file="$SSL_BASE/$primary/cert.pem"
    fi

    end_time=""
    src=""

   
    if [ "$PREFER_LOCAL_CERT" -eq 1 ]; then
      end_time="$(get_end_time_from_file "$cert_file" || true)"
      if [ -n "${end_time:-}" ]; then
        src="LOCAL"
      fi
    fi

 
    if [ -z "${end_time:-}" ]; then
      end_time="$(get_cert_end_time_remote "$primary" || true)"
      if [ -n "${end_time:-}" ]; then
        src="REMOTE"
      fi
    fi

    if [ -z "${end_time:-}" ]; then
   
      if [ -s "$cert_file" ]; then
        printf "%-30s %-10s %-8s %-12s %-24s\n" "$primary" "$type" "ERR" "ERR" "remote unreachable"
      else
        printf "%-30s %-10s %-8s %-12s %-24s\n" "$primary" "$type" "ERR" "ERR" "no local cert + unreachable"
      fi
      continue
    fi

    left_days="$(days_left_from_endtime "$end_time" || true)"
    if [ -z "${left_days:-}" ]; then
      printf "%-30s %-10s %-8s %-12s %-24s\n" "$primary" "$type" "$src" "ERR" "bad date"
      continue
    fi

    printf "%-30s %-10s %-8s %-12s %-24s\n" "$primary" "$type" "$src" "$left_days" "$end_time"

  done < <(find "$dir_path" -maxdepth 1 -type d -name "*_ecc" -print0)

  echo
}


for arg in "$@"; do
   case "${arg}" in
     tool) tool; exit 0 ;;
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
     fixsshd) fixsshd; exit 0 ;;
     devssl) devssl; exit 0 ;;
     sslcheck) wnmp_sslcheck; exit 0 ;;
     ssltest) wnmp_ssltest; exit 0 ;;
     cf) cf; exit 0 ;;
     "") ;;
     *) echo "[setup] Unknown parameter: ${arg}"; usage; exit 1 ;;
   esac
 done



is_lan
detect_cn_ip || true
aptinit

if [[ "$IS_CN" -eq 1 ]]; then
    enable_proxy

    if [[ "${PROXY_MODE:-}" != "DIRECT" ]]; then
      if ! proxy_healthcheck; then
        disable_proxy
      fi
    fi
fi







install -m 0644 /dev/stdin /etc/profile.d/wnmp-path.sh <<'EOF'
# WNMP: global PATH for login/interactive shells
export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:${PATH}"
EOF

if ! grep -q 'wnmp-path.sh' /etc/bash.bashrc 2>/dev/null; then
  printf '\n# WNMP PATH for interactive shells\n[ -f /etc/profile.d/wnmp-path.sh ] && . /etc/profile.d/wnmp-path.sh\n' >> /etc/bash.bashrc
fi

export PATH="/usr/local/php/bin:/usr/local/mariadb/bin:${PATH}"
hash -r

echo -e "${GREEN}PATH 已写入 /etc/profile.d/wnmp-path.sh，并注入 /etc/bash.bashrc；当前会话已生效。${NC}"
echo -e "${GREEN}php 路径：$(command -v php || echo '未找到')${NC}"

PHP="/usr/local/php/bin/php"
PHPIZE="/usr/local/php/bin/phpize"
PHPCONFIG="/usr/local/php/bin/php-config"


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
    "php8.2") php_version='8.2.30'; break ;;
    "php8.3") php_version='8.3.30'; break ;;
    "php8.4") php_version='8.4.17'; break ;;
    "php8.5") php_version='8.5.2'; break ;;
    *) echo "无效选项 $REPLY";;
  esac
done

echo "请选择mariadb版本:"
mariadbselcect=''
mariadb_version='0'
select mariadbselcect in "不安装mariadb" "1GB内存10.6" "2GB以上内存10.11" "4GB以上内存11.8.5"; do
  case $mariadbselcect in
    "不安装mariadb") mariadb_version='0'; break ;;
    "1GB内存10.6") mariadb_version='10.6.24'; break ;;
    "2GB以上内存10.11") mariadb_version='10.11.15'; break ;;
    "4GB以上内存11.8.5") mariadb_version='11.8.5'; break ;;
    *) echo "无效选项 $REPLY";;
  esac
done
if [ "$mariadb_version" != "0" ]; then
  read -p "请输入要设置的 MySQL root 密码 [默认: needpasswd]: " MYSQL_PASS
  MYSQL_PASS=${MYSQL_PASS:-needpasswd}
fi
read -rp "是否安装NGINX？(y/n): " choosenginx


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



apt --fix-broken install -y
apt autoremove -y
apt update
apt install -y net-tools libc-ares-dev apache2-utils git liblzma-dev libedit-dev libncurses5-dev libnuma-dev libaio-dev libsnappy-dev libicu-dev liblz4-dev screen build-essential liburing-dev liburing2 \
  libzstd-dev wget curl m4 autoconf re2c pkg-config libxml2-dev libsodium-dev libcurl4-openssl-dev \
  libbz2-dev openssl libssl-dev libtidy-dev libxslt1-dev libsqlite3-dev zlib1g-dev \
  libpng-dev libjpeg-dev libwebp-dev libonig-dev libzip-dev libpcre2-8-0 libpcre2-dev \
  cmake bison libncurses-dev libfreetype-dev unzip
  
git config --global http.version HTTP/1.1 || true
export CURL_HTTP_VERSION=1.1
export CURL_RETRY=20
export CURL_RETRY_DELAY=2

ensure_group www
ensure_user  www www


if [ "$php_version" != "0" ]; then
  cd "$WNMPDIR"
  purge_php || true
  php_tar="php-$php_version.tar.gz"
  php_dir="php-$php_version"
  
  if [ ! -f "$php_tar" ]; then
    rm -rf "$php_dir"
    php_url="https://www.php.net/distributions/$php_tar"
    download_with_mirrors "$php_url" "$WNMPDIR/$php_tar"
    
  fi
  tar zxvf "$php_tar"
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
  "--enable-fileinfo"
  "--with-sodium"
  "--enable-soap"
  "--enable-phar"
  "--disable-zts" 
  "--disable-rpath"
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
  "--enable-posix"
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
opcache.revalidate_freq=0

opcache.save_comments=1
opcache.enable_file_override=0

opcache.jit=off
opcache.jit_buffer_size=0


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
opcache.revalidate_freq=0

opcache.save_comments=1
opcache.enable_file_override=0

opcache.jit=off
opcache.jit_buffer_size=0


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

  cd "$WNMPDIR"

  if [ ! -f "pie.phar" ]; then
   download_with_mirrors "https://github.com/php/pie/releases/latest/download/pie.phar" "$WNMPDIR/pie.phar"
   
  fi

  cp "$WNMPDIR"/pie.phar /usr/local/php/bin/pie && chmod +x /usr/local/php/bin/pie


rm -rf swoole-src
if [[ "$php_version" =~ ^8\.5\. ]]; then
  if [ ! -f ""$WNMPDIR"/swoole.tar.gz" ]; then

     download_with_mirrors "https://github.com/swoole/swoole-src/archive/master.tar.gz" "$WNMPDIR/swoole.tar.gz"
  fi 
else
  if [ ! -f ""$WNMPDIR"/swoole.tar.gz" ]; then
    download_with_mirrors "https://github.com/swoole/swoole-src/archive/refs/tags/v6.1.4.tar.gz" "$WNMPDIR/swoole.tar.gz"
    
  fi
  
fi
  
  tar zxvf ./swoole.tar.gz && \
  mv swoole-src* swoole-src && \
  cd swoole-src && \
  phpize && \
  ./configure --with-php-config=/usr/local/php/bin/php-config \
  --enable-openssl  --enable-mysqlnd --enable-swoole-curl --enable-cares --enable-iouring --enable-zstd && \
  make && make install
  
  /usr/local/php/bin/pie install phpredis/phpredis
  /usr/local/php/bin/pie install arnaud-lb/inotify
  /usr/local/php/bin/pie install apcu/apcu
 

else
  echo '不安装php'
fi


case "$choosenginx" in
  y|Y|yes|YES|Yes)
    purge_nginx || true
    cd "$WNMPDIR"
    apt-get install -y cron curl socat tar coreutils
    systemctl enable --now cron
    download_with_mirrors "https://get.acme.sh" "$WNMPDIR/acme.sh.install"   
    sh acme.sh.install email=1@gmail.com    
    ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

    bash /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    if [ ! -s /root/.acme.sh/ca/acme-v02.api.letsencrypt.org/account.key ]; then
      /root/.acme.sh/acme.sh --register-account -m 1@gmail.com --server letsencrypt
    fi


    if [[ "$IS_LAN" -eq 0 ]]; then 
        
 
        echo "$PUBLIC_IP"
        if acme.sh --issue --server letsencrypt -d "$PUBLIC_IP" --certificate-profile shortlived --standalone; then
            echo "[成功] 证书申请成功"
        else
            IS_LAN=1
            echo "[提示] 证书申请失败，IS_LAN 已切换为 1"
        fi
    fi


    mkdir -p /home/wwwroot/default
    mkdir -p /home/wwwlogs
    mkdir -p /home/passwd
    htpasswd -bc /home/passwd/.default wnmp "${MYSQL_PASS:-needpasswd}"
    chown -R www:www /home/passwd
    chown -R www:www /home/wwwroot
    chown -R www:www /home/wwwlogs

    

    if [ ! -f "$WNMPDIR/nginx.tar.gz" ]; then
      rm -rf nginx
      download_with_mirrors "https://nginx.org/download/nginx-1.29.5.tar.gz" "$WNMPDIR/nginx.tar.gz"
      mkdir -p tmp && tar zxf nginx.tar.gz -C tmp && mv tmp/* nginx && rm -rf tmp
      
      cd nginx
      git --version >/dev/null || { log "git missing"; exit 1; }
      git_clone_wnmp https://github.com/arut/nginx-dav-ext-module.git
     
      
    else
      rm -rf nginx
      mkdir -p tmp && tar zxf nginx.tar.gz -C tmp && mv tmp/* nginx && rm -rf tmp
      cd nginx
      git --version >/dev/null || { log "git missing"; exit 1; }
      rm -rf nginx-dav-ext-module
      git_clone_wnmp https://github.com/arut/nginx-dav-ext-module.git
    fi
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
      --with-http_v3_module \
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

cat <<'EOF' >  /usr/local/nginx/cloudflare-ips.conf
# Cloudflare IP ranges - auto generated
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;
EOF

cat <<'EOF' >  /usr/local/nginx/block.conf
if ($request_uri ~ "^//+") { return 444; }
location ~* /wp-(admin|includes|content)/ { access_log off; return 444; }
location ~* /(wp-login\.php|xmlrpc\.php|wlwmanifest\.xml)$ { access_log off; return 444; }

location ~* ^/\.(git|svn|hg|bzr)(/|$) {access_log off; return 444; }
location ~* ^/\.DS_Store$ {access_log off; return 444; }
location ~* ^/\.(env|env\..*|htaccess|htpasswd)$ {access_log off; return 444; }
location ~* ^/(composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml)$ {access_log off; return 444; }

location ~* \.(bak|old|orig|save|swp|swo|tmp|temp)$ {access_log off; return 444; }
location ~* \.(sql|sqlite|dump)$ {access_log off; return 444; }
location ~* ^/(backup|backups|bak|dump|dumps|sql|db|database)(/|$) {access_log off; return 444; }

location ~* ^/(phpinfo\.php|info\.php|test\.php|_debug|debug)(/|$) {access_log off; return 444; }
location ~* ^/(install|installer|setup|configure)(/|$) {access_log off; return 444; }

location ~* ^/vendor/phpunit/ {access_log off; return 444; }
location ~* ^/phpunit(\.xml|\.xml\.dist)?$ {access_log off; return 444; }
location ~* ^/storage/ {access_log off; return 444; }
location ~* ^/public/storage/ {access_log off; return 444; }
location ~* ^/runtime/ {access_log off; return 444; }
location ~* ^/bootstrap/cache/ {access_log off; return 444; }

location ~* ^/(shell|cmd|webshell|wso|b374k|c99|r57)\.php$ {access_log off; return 444; }
location ~* ^/(tinyfilemanager|filemanager|elfinder)(/|$) {access_log off; return 444; }
location ~* ^/(crossdomain\.xml|clientaccesspolicy\.xml)$ {access_log off; return 444; }

location ~* \.\./ { access_log off; return 444; }
location ~* %2e%2e%2f { access_log off; return 444; }
EOF

cat <<'EOF' >  /usr/local/nginx/download.html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
  <title>Download</title>
  <meta name="color-scheme" content="light dark">
  <style>
    :root{
      --bg: #0b1220;
      --card:#0f1a2e;
      --card2:#0c1527;
      --text:#e6eefc;
      --muted:#9bb0d1;
      --line: rgba(255,255,255,.08);
      --accent:#4da3ff;
      --good:#34d399;
      --warn:#fbbf24;
      --shadow: 0 12px 30px rgba(0,0,0,.35);
      --radius:18px;
    }
    @media (prefers-color-scheme: light){
      :root{
        --bg:#f6f8fc;
        --card:#ffffff;
        --card2:#f7f9ff;
        --text:#0f172a;
        --muted:#64748b;
        --line: rgba(15,23,42,.10);
        --accent:#2563eb;
        --shadow: 0 12px 30px rgba(15,23,42,.10);
      }
    }
    *{box-sizing:border-box}
    body{
      margin:0;
      font-family: ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji";
      background: radial-gradient(900px 600px at 10% 0%, rgba(77,163,255,.18), transparent 60%),
                  radial-gradient(900px 600px at 100% 20%, rgba(52,211,153,.14), transparent 55%),
                  var(--bg);
      background-repeat: no-repeat;
      color: var(--text);
    }
    a{color:inherit;text-decoration:none}
    .wrap{max-width:1100px;margin:0 auto;padding:24px 16px 44px}
    .topbar{
      display:flex;gap:12px;align-items:center;justify-content:space-between;
      padding:14px 16px;border:1px solid var(--line);
      border-radius: var(--radius);
      background: color-mix(in oklab, var(--card) 92%, transparent);
      box-shadow: var(--shadow);
      backdrop-filter: blur(10px);
    }
    .brand{display:flex;gap:10px;align-items:center;min-width:0}
    .logo{
      width:38px;height:38px;border-radius:14px;
      background: linear-gradient(135deg, rgba(77,163,255,.95), rgba(52,211,153,.85));
      box-shadow: 0 10px 22px rgba(77,163,255,.18);
      position:relative;flex:0 0 auto;
    }
    .logo:after{
      content:"";position:absolute;inset:9px;border-radius:10px;
      background: rgba(255,255,255,.18);
      border:1px solid rgba(255,255,255,.18);
    }
    .title{display:flex;flex-direction:column;min-width:0}
    .title b{font-size:14px;letter-spacing:.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .title span{font-size:12px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .actions{display:flex;gap:10px;align-items:center;flex:0 0 auto}
    .btn{
      border:1px solid var(--line);
      background: color-mix(in oklab, var(--card2) 85%, transparent);
      color: var(--text);
      padding:10px 12px;border-radius:14px;
      font-size:13px;cursor:pointer;
      display:inline-flex;gap:8px;align-items:center;
      transition: transform .12s ease, border-color .12s ease;
      user-select:none;
    }
    .btn:hover{transform: translateY(-1px); border-color: color-mix(in oklab, var(--accent) 50%, var(--line))}
    .btn:active{transform: translateY(0)}
    .btn .dot{
      width:8px;height:8px;border-radius:99px;background: var(--accent);
      box-shadow: 0 0 0 5px color-mix(in oklab, var(--accent) 20%, transparent);
    }
    .grid{display:grid;grid-template-columns: 1fr;gap:14px;}
    .panel{
      border:1px solid var(--line);
      border-radius: var(--radius);
      background: color-mix(in oklab, var(--card) 92%, transparent);
      box-shadow: var(--shadow);
      overflow:hidden;
    }
    .panel-hd{
      padding:14px 16px;display:flex;gap:12px;align-items:center;justify-content:space-between;
      border-bottom:1px solid var(--line);
    }
    .crumbs{display:flex;gap:8px;align-items:center;min-width:0;flex-wrap:wrap}
    .crumb{
      display:inline-flex;gap:6px;align-items:center;
      padding:8px 10px;border-radius:12px;
      border:1px solid var(--line);
      background: color-mix(in oklab, var(--card2) 86%, transparent);
      font-size:13px;max-width:100%;
    }
    .crumb:hover{border-color: color-mix(in oklab, var(--accent) 45%, var(--line))}
    .crumb .sep{opacity:.55}
    .search{
      display:flex;align-items:center;gap:10px;
      padding:10px 12px;border-radius:14px;
      border:1px solid var(--line);
      background: color-mix(in oklab, var(--card2) 86%, transparent);
      min-width:260px;max-width:420px;width:40%;
    }
    .search input{
      width:100%;border:none;outline:none;
      background:transparent;color:var(--text);font-size:13px;
    }
    .search input::placeholder{color: color-mix(in oklab, var(--muted) 90%, transparent)}
    .table{width:100%;border-collapse:collapse}
    .table th,.table td{
      padding:12px 14px;border-bottom:1px solid var(--line);
      text-align:left;font-size:13px;
    }
    .table th{color:var(--muted);font-weight:600}
    .row{
      display:flex;align-items:center;gap:12px;min-width:0;
    }
    .icon{
      width:36px;height:36px;border-radius:14px;
      display:grid;place-items:center;
      border:1px solid var(--line);
      background: color-mix(in oklab, var(--card2) 88%, transparent);
      flex:0 0 auto;
    }
    .name{min-width:0; max-width: 70dvw}
    .name b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .name span{display:block;font-size:12px;color:var(--muted);margin-top:2px}
    .op{
      padding:8px 10px;border-radius:12px;border:1px solid var(--line);
      background: color-mix(in oklab, var(--card2) 88%, transparent);
      cursor:pointer;font-size:12px;color:var(--text);
    }
    .op:hover{border-color: color-mix(in oklab, var(--accent) 45%, var(--line))}
   
    .muted{color:var(--muted)}
    .muted.last{display: flex; justify-content: space-between; align-items: center;}
    .empty{padding:22px 16px;color:var(--muted);text-align:center}
    .toast{
      position:fixed;left:50%;bottom:18px;transform:translateX(-50%);
      background: color-mix(in oklab, var(--card) 92%, transparent);
      border:1px solid var(--line);
      box-shadow: var(--shadow);
      padding:10px 12px;border-radius:14px;
      font-size:13px;display:none;gap:8px;align-items:center;
      backdrop-filter: blur(10px);
    }
    .toast.show{display:inline-flex}
    .toast .dot{width:8px;height:8px;border-radius:99px;background:var(--good)}
    .copyright{display: flex; justify-content: center; color: #555; line-height: 1.5; font-size: 12px; margin: 5px 0}
    @media (max-width:720px){
      .wrap{padding:10px 5px}
      .table th{display: none}
      .table tr{display: block; margin: 10px 0; padding: 0 10px}
      .table td{

        display: flex;
        padding:5px 0;
        line-height: 1.5;
        justify-content: space-between;
        align-items: center;
      }
      .table td:first-child:before{display: block; content: '名称'}
      .table td:nth-child(2):before{display: block; content: '大小'}
      .table td:last-child:before{display: block; content: '日期'}
      .search{min-width:0;width:100%;max-width:none}
      .panel-hd{flex-direction:column;align-items:stretch}
      .actions{display:none}
      
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="topbar">
      <div class="brand">
        <div class="logo" aria-hidden="true"></div>
        <div class="title">
          <b id="pageTitle">Downloads</b>
          <span id="pageSub">/</span>
        </div>
      </div>
      <div class="actions">
        <button class="btn" id="btnReload"><span class="dot"></span>刷新</button>
        <button class="btn" id="btnCopyPath">复制当前路径</button>
      </div>
    </div>
    <div class="copyright"><small>本服务器由 <a href="https://wnmp.org" target="_blank" rel="noopener">wnmp.org</a> 一键包构建 </small></div>
    <div class="grid">
      <div class="panel">
        <div class="panel-hd">
          <div class="crumbs" id="crumbs"></div>
          <div class="search">
            <span class="muted">🔎</span>
            <input id="q" placeholder="搜索文件名…（支持模糊匹配）" />
          </div>
        </div>

        <table class="table">
          <thead>
            <tr>
              <th style="width:58%">名称</th>
              <th>大小</th>
              <th>修改时间</th>
              
            </tr>
          </thead>
          <tbody id="tbody">
            <tr><td colspan="3" class="empty">加载中…</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <div class="toast" id="toast"><span class="dot"></span><span id="toastText">已复制</span></div>

<script>
(() => {
  const $ = (s) => document.querySelector(s);

  const tbody = $("#tbody");
  const crumbs = $("#crumbs");
  const q = $("#q");
  const pageSub = $("#pageSub");
  const pageTitle = $("#pageTitle");
  const toast = $("#toast");
  const toastText = $("#toastText");

  function showToast(msg){
    toastText.textContent = msg;
    toast.classList.add("show");
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toast.classList.remove("show"), 1400);
  }

  function fmtSize(n){
    if (n == null || n === "") return "-";
    const x = Number(n);
    if (!isFinite(x)) return "-";
    const u = ["B","KB","MB","GB","TB"];
    let i=0, v=x;
    while (v>=1024 && i<u.length-1){ v/=1024; i++; }
    return (i===0 ? v.toFixed(0) : v.toFixed(2).replace(/\.00$/,"")) + " " + u[i];
  }

  function esc(s){
    return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  }

  function currentDirPath(){

    let p = decodeURIComponent(location.pathname || "/");
    if (!p.endsWith("/")) {

      p = p.substring(0, p.lastIndexOf("/") + 1) || "/";
    }
    return p;
  }

  function buildCrumbs(p){
    crumbs.innerHTML = "";
    const parts = p.split("/").filter(Boolean);
    const items = [{name:"root", path:"/"}];
    let acc = "/";
    for (const seg of parts){
      acc += seg + "/";
      items.push({name: seg, path: acc});
    }
    items.forEach((it, idx) => {
      const a = document.createElement("a");
      a.className = "crumb";
      a.href = it.path;
      a.innerHTML = idx===0 ? "🏠 <span class='muted'>/</span>" : `${esc(it.name)} <span class="sep">/</span>`;
      crumbs.appendChild(a);
    });
  }

  async function load(){
    const dir = currentDirPath();
    pageSub.textContent = dir;
    pageTitle.textContent = "Downloads";
    buildCrumbs(dir);

 
    const api = "/api/list" + dir;

    tbody.innerHTML = `<tr><td colspan="4" class="empty">加载中…</td></tr>`;
    let data;
    try{
      const res = await fetch(api, {cache:"no-store"});
      if (!res.ok) throw new Error("HTTP " + res.status);
      data = await res.json();
    }catch(e){
      tbody.innerHTML = `<tr><td colspan="4" class="empty">加载失败：${esc(e.message || e)}<br><span class="muted">请检查 Nginx 是否已开启 /api/list/ 的 autoindex_format json</span></td></tr>`;
      return;
    }

   
    let list = Array.isArray(data) ? data.slice() : [];

   
    list.sort((a,b) => {
      const ad = (a.type === "directory") ? 0 : 1;
      const bd = (b.type === "directory") ? 0 : 1;
      if (ad !== bd) return ad - bd;
      return String(a.name).localeCompare(String(b.name));
    });

    render(list, q.value.trim());
  }

  function render(list, keyword){
    const dir = currentDirPath();
    let filtered = list;

    if (keyword){
      const k = keyword.toLowerCase();
      filtered = list.filter(x => String(x.name || "").toLowerCase().includes(k));
    }

    if (!filtered.length){
      tbody.innerHTML = `<tr><td colspan="4" class="empty">空目录 / 没有匹配项</td></tr>`;
      return;
    }

    const rows = filtered.map(it => {
      const name = it.name || "";
      const isDir = it.type === "directory";
      const href = isDir ? (dir + name.replace(/\/?$/,"/")) : (dir + name);
      const size = isDir ? "-" : fmtSize(it.size);
      const mtime = it.mtime ? new Date(it.mtime).toLocaleString() : "-";
      const icon = isDir ? "📁" : "📄";
      return `
        <tr>
          <td>
            <a href="${esc(href)}">
              <div class="row">
                <div class="icon" aria-hidden="true">${icon}</div>
                <div class="name">
                  <b title="${esc(name)}">${esc(name)}</b>
                  
                </div>
              </div>
            </a>
          </td>
          <td class="muted">${esc(size)}</td>
          <td class="muted last">${esc(mtime)}<button class="op" data-copy="${esc(location.origin + href)}">复制</button></td>
          
        </tr>
      `;
    }).join("");

    tbody.innerHTML = rows;

    tbody.querySelectorAll("[data-copy]").forEach(btn => {
      btn.addEventListener("click", async (e) => {
        const text = e.currentTarget.getAttribute("data-copy");
        const ta = document.createElement("textarea");
          ta.value = text; 
          document.body.appendChild(ta);
          ta.select(); document.execCommand("copy");
          ta.remove();
          showToast("已复制链接");
      });
    });
  }

  $("#btnReload")?.addEventListener("click", load);
  $("#btnCopyPath")?.addEventListener("click", async () => {
    const dir = location.origin + currentDirPath();
    try{
      await navigator.clipboard.writeText(dir);
      showToast("已复制当前路径");
    }catch{
      showToast("复制失败（权限限制）");
    }
  });

  q.addEventListener("input", async () => {
    const dir = currentDirPath();
    const api = "/api/list" + dir;
    try{
      const res = await fetch(api, {cache:"no-store"});
      const data = await res.json();
      const list = Array.isArray(data) ? data.slice() : [];
      list.sort((a,b) => ((a.type==="directory")?0:1)-((b.type==="directory")?0:1) || String(a.name).localeCompare(String(b.name)));
      render(list, q.value.trim());
    }catch{
      
    }
  });

  load();
})();
</script>
</body>
</html>


EOF

cat <<'EOF' >  /usr/local/nginx/download.conf
types { }
default_type application/octet-stream;

charset utf-8;
sendfile on;
aio on;
directio 4m;
output_buffers 1 512k;

location = / {
    default_type text/html;
    add_header Content-Type "text/html; charset=utf-8" always;
    root /usr/local/nginx;
    try_files /download.html =404;
}


location ~ ^/.*/$ {
    default_type text/html;
    add_header Content-Type "text/html; charset=utf-8" always;
    root /usr/local/nginx;
    try_files /download.html =404;
}

location ^~ /api/list/ {
    root $dl_site_root;

    autoindex on;
    autoindex_format json;
    autoindex_exact_size off;
    autoindex_localtime on;

    default_type application/json;
    add_header Cache-Control "no-store" always;

    rewrite ^/api/list/(.*)$ /$1 break;
}


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
    <p style="font-size:0.9rem;opacity:0.7;">该服务器使用<a style="color:#555" href="https://www.wnmp.org" target="_blank">wnmp.org</a>的一键安装包搭建而成。</p>
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
    <p style="font-size:0.9rem;opacity:0.7;">该服务器使用<a style="color:#555" href="https://www.wnmp.org" target="_blank">wnmp.org</a>的一键安装包搭建而成。</p>
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
    keepalive_timeout   30s;
    keepalive_requests  100000;

    proxy_request_buffering on;
    
    client_body_temp_path /usr/local/nginx/client_body_temp 1 2;
    client_max_body_size 10g;
    client_body_buffer_size 512k;
    client_header_timeout 300s;
    client_body_timeout   1800s;
    send_timeout          1800s;

    include cloudflare-ips.conf;
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

    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';
    map $status $log_ok {
        default 1;
        301     0;
        444     0;
    }

    upstream lowphp {
        server unix:/tmp/lowphp.sock;
        keepalive 100000;
    }
    

    server {
        listen 80 default_server;
        server_name _;
        root  /home/wwwroot/default;
        index index.html index.php;
        include block.conf;
        error_page 403 =403 @e403;

        location @e403 {
            root html;
            internal;
            default_type text/html;
            try_files /403.html =403;
        }

        error_page 404 =404 @e404;

        location @e404 {
            root html;
            internal;
            default_type text/html;
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
        location ~ /\.(?!well-known) {deny all;}
        
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
    map $host $dl_site_root {
        default                 /home/wwwroot/$host;
        ~^www\.(?<d>.+)$        /home/wwwroot/$d;
    }
    include       mime.types;
    default_type  application/octet-stream;
    dav_ext_lock_zone zone=webdav_locks:10m;
    aio threads;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout   30s;
    keepalive_requests  100000;

    proxy_request_buffering on;
    
    client_body_temp_path /usr/local/nginx/client_body_temp 1 2;
    client_max_body_size 10g;
    client_body_buffer_size 512k;
    client_header_timeout 300s;
    client_body_timeout   1800s;
    send_timeout          1800s;

    include cloudflare-ips.conf;
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

    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';
    map $status $log_ok {
        default 1;
        301     0;
        444     0;
    }

    upstream lowphp {
        server unix:/tmp/lowphp.sock;
        keepalive 100000;
    }
    

    server {
        listen 80 default_server;
        listen 443 ssl  default_server reuseport;
        listen [::]:443 ssl default_server reuseport;
        #listen 443 quic default_server reuseport;
        #listen [::]:443 quic default_server reuseport;
        http2 on;
        #http3 on;
        server_name _;
        if ($server_port = 80 ) {
            return 301 https://$host$request_uri;
        }
        root  /home/wwwroot/default;
        index index.html index.php;
        include block.conf;
        error_page 403 =403 @e403;

        location @e403 {
            root html;
            internal;
            default_type text/html;
            try_files /403.html =403;
        }

        error_page 404 =404 @e404;

        location @e404 {
            root html;
            internal;
            default_type text/html;
            try_files /404.html =404;
        }
        ssl_certificate     /usr/local/nginx/ssl/default/cert.pem;
        ssl_certificate_key /usr/local/nginx/ssl/default/key.pem;
        
        ssl_session_cache   shared:SSL:20m;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
        ssl_prefer_server_ciphers on;
        ssl_session_timeout 10m;
        ssl_early_data off;
        #quic_retry on;
        #add_header Alt-Svc 'h3=":443"; ma=86400' always;
        #add_header QUIC-Status $http3 always;
        
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
        location ~ /\.(?!well-known) {deny all;}

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
      acme.sh --install-cert -d "$PUBLIC_IP" --ecc --key-file  /usr/local/nginx/ssl/default/key.pem  --fullchain-file /usr/local/nginx/ssl/default/cert.pem  || true
    fi

    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx

    if [ ! -x /usr/bin/nginx ]; then
        ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx
    fi
    
    wnmp_sslcheck
    cf
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
  purge_mariadb || true

  cd "$WNMPDIR"

  ensure_group mariadb
  ensure_user  mariadb mariadb
  mkdir -p /home/mariadb
  mkdir -p /home/mariadb/binlog
  chown -R mariadb:mariadb /home/mariadb


  if [ ! -f "$WNMPDIR/mariadb-$mariadb_version.tar.gz" ]; then
    rm -rf "mariadb-$mariadb_version"
   download_with_mirrors "https://archive.mariadb.org/mariadb-$mariadb_version/source/mariadb-$mariadb_version.tar.gz" "$WNMPDIR/mariadb-$mariadb_version.tar.gz"
    
  fi

  tar zxvf "mariadb-$mariadb_version.tar.gz"

  cd "mariadb-$mariadb_version"
 
  rm -rf build
  
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

  cd "$WNMPDIR"
  


    if [ ! -f "$WNMPDIR/phpmyadmin.zip" ]; then
      download_with_mirrors "https://files.phpmyadmin.net/phpMyAdmin/5.2.3/phpMyAdmin-5.2.3-all-languages.zip" "$WNMPDIR/phpmyadmin.zip"
    fi
    cd /home/wwwroot/default
    rm -rf phpmyadmin phpmyadmin.zip
    cp "$WNMPDIR"/phpmyadmin.zip /home/wwwroot/default
    apt install -y unzip
    unzip phpmyadmin.zip -d ./
    mv phpMyAdmin* phpmyadmin
    rm -f phpmyadmin.zip
    chown -R www:www /home/wwwroot
  cd "$WNMPDIR"
  install_mroonga

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

wnmp_kernel_tune
