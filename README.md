# 🌀 WNMP — One-Click Web Stack
**WebDAV · Nginx · MariaDB · PHP · Kernel Optimization**
[🇨🇳 中文版说明](./README.zh.md)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13%20%7C%20Ubuntu%2022--25-green.svg)
![Build](https://img.shields.io/badge/Installer-One%20Command-orange.svg)

> Lightweight · Stable · Reproducible  
> A one-click shell installer for building a production-ready web stack with **WebDAV, Nginx, PHP, MariaDB (Mroonga engine)** and automatic kernel/network tuning.

---

# WNMP = WebDAV + Nginx + MariaDB + PHP

## 🚀 Overview

**WNMP** installs Nginx, PHP, and MariaDB with a single command, configures SSL via `acme.sh`, sets up WebDAV, applies BBR/FQ tuning, and safely disables THP.

It’s designed for **small to medium websites, edge nodes, and private deployments**, providing a stable and reproducible runtime environment.

---

## ✨ Core Features

- **Ready-to-Use Web Runtime**  
  Compiles latest Nginx (1.28.0) with `dav-ext`, `http2`, and `stream` modules.  
  Supports PHP 8.2–8.5 and MariaDB 10.6 / 10.11.

- **Kernel & Network Optimization**  
  Enables BBR/FQ, tunes `somaxconn` and file descriptors, disables THP.  
  Auto-writes to `/etc/sysctl.conf` and `/etc/security/limits.conf`.

- **Automatic SSL Certificates**  
  Integrates `acme.sh`.  
  Uses **Cloudflare DNS-01** first, falls back to **webroot**, then automatically reloads Nginx.

- **Multi-Site & WebDAV**  
  One-click vhost creation, built-in phpMyAdmin protection, and WebDAV account management.  
  Each domain uses an independent password file under `/home/passwd/`.

- **Maintainable Directory Layout**
  ```
  /usr/local/nginx
  /usr/local/php
  /home/wwwroot
  ```

- **Security by Default**
  - Hidden & sensitive file types disabled  
  - Reasonable timeouts/caching  
  - Unused PHP options turned off  

---

## ⚙️ Installation

```bash
apt install -y curl
curl -fL https://wnmp.org/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

License: **GPLv3**  
Run as **root**.

---

## 💡 Common Commands

| Purpose | Command |
|----------|----------|
| Normal Installation | `bash wnmp.sh` |
| Check Status | `bash wnmp.sh status` |
| SSH Key Login | `bash wnmp.sh sshkey` |
| Add WebDAV Account | `bash wnmp.sh webdav` |
| Configure Default Site & Certificate | `bash wnmp.sh default` |
| Create New Virtual Host (with SSL) | `bash wnmp.sh vhost` |
| Kernel/Network Optimization Only | `bash wnmp.sh tool` |
| Restart All Services | `bash wnmp.sh restart` |
| Cleanup | `bash wnmp.sh remove` / `bash wnmp.sh renginx` / `bash wnmp.sh rephp` / `bash wnmp.sh remariadb` |

---

## 🌐 Optional Footer Badge

```html
<small>This server is built by <a href="https://wnmp.org" target="_blank" rel="noopener">wnmp.org</a> one-click installer</small>
```

---
Does it support one-click generation of SSH login keys?
Yes. Run bash wnmp.sh sshkey

=====================================================================

⚠️ Important reminder: Before confirming you have saved the private key to your own computer

⚠️ Do not disconnect the current SSH session, or you will be unable to log back into the server!

=====================================================================

Save the private key to your local computer. You can then load the key in an SSH client for password-less login.

After configuring key-based login, the server will block all username/password logins.
---

---

## 📖 License

Released under the **GNU General Public License v3.0 (GPLv3)**  
You may use, modify, and redistribute under the same license terms.

---

## 🤝 Community

- **Official Site:** [https://wnmp.org](https://wnmp.org)
- **QQ Group:** 1075305476  
- **Telegram:** [t.me/wnmps](https://t.me/wnmps)
- **License:** [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
