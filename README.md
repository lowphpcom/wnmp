# 🌀 WNMP — One-Click Web Stack-For the complete tutorial, visit the official website at [wnmp.org](https://wnmp.org).
**Windows11(WSL)+Linux(Debian,Ubuntu) · Nginx · Mariadb(Mroonga) · PHP · WebDav · Kernel Optimization**
---
[🇨🇳 中文版说明](./README.zh.md)
---
![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13%20%7C%20Ubuntu%2022--25-green.svg)
![Build](https://img.shields.io/badge/Installer-One%20Command-orange.svg)

##  Let's Encrypt IP certificate protection is now supported by default.

## The wnmp.org one-click web environment installation package has been officially recognized by the Mroonga search engine and has been listed with a backlink on the official Mroonga users page.
https://mroonga.org/users/




> Lightweight · Stable · Reproducible  
> A one-click shell On Windows11(WSL)+Linux(Debian,Ubuntu) installer for building a production-ready web stack with **Nginx, PHP, MariaDB (Mroonga engine),WebDAV** and automatic kernel/network tuning.

---

## WNMP：

## 1、Windows11(WSL)+Nginx+Mariadb(Mroonga)+PHP
<span style="color:#DC2626;">(Deployed in a Linux subsystem running on Windows 11 - WSL, **not** an .exe environment package)</span>
## 2、(Linux)WebDav+Nginx+Mariadb(Mroonga)+PHP

## Core Objectives of WNMP
WNMP is not merely about “packaging Nginx + PHP + MariaDB into a container.” Its purpose is to achieve host-level performance tuning and baseline security configuration (kernel network parameters, ulimit restrictions, SSH key setup, compilation optimizations, etc.) with a single click in a clean system environment.

## Why Docker is Not Suitable
These host-level capabilities are often uncontrollable within containers or require high privileges like --privileged, which undermines the fundamental purpose of container isolation.

## Recommended Deployment Methods
Therefore, WNMP is recommended for use on KVM virtual machines, cloud servers, or KVM virtual systems running within Proxmox (PVE) to fully leverage its performance tuning and system optimization advantages.


## Update Log

v1.39 HTTP/3 has been reverted to an optional configuration. Under packet loss conditions, it cannot leverage the Linux kernel BBR congestion control algorithm, which may cause static resource requests to stall. If you need to enable it, please uncomment the relevant settings in the site’s Nginx configuration file.

v1.38 NGINX defaults to version v1.29.5, fixes known vulnerabilities, and enables the h3 protocol.If a firewall is present, please ensure UDP port 443 is open to enable HTTP/3 properly!

v1.37 Added `wnmp cf` for standalone installation to capture Nginx logs revealing genuine client IPs after Cloudflare CDN proxy, with scheduled tasks for automatic updates to the official CF IP list.

v1.36 Provides UI support for Nginx open directory clean download sites. It is not an additional program but a UI enhancement for Nginx autoindex. Simply execute `wnmp vhost` and select [yes] for the open directory option to experience it. Demo:[bb.wnmp.org](https://bb.wnmp.org)

v1.35 Added block.conf to default block common botnet scan requests, keeping Nginx logs cleaner. Added Nginx global variables so other scripts can properly detect the Nginx environment!

v1.34 Added custom SSL check cron tasks `wnmp sslcheck` and `wnmp ssltest` to replace the default `acme.sh` cron job. These enable intelligent certificate renewal for short-lived domain and IP certificates. The official ACME renewal script fails to recognize the 6-day validity period for IP certificates and cannot automatically restart Nginx, resulting in failed IP certificate renewals.

v1.33 Added `wnmp devssl` self-signed certificate, suitable for local development environments on Windows 11 WSL subsystem to handle HTTPS requests.

v1.28 Added global variable `wnmp` all commands can now be executed from any directory

v1.26 Enables built-in PHP support for fileinfo, soap, and sodium extensions.

v1.20 All software downloads are saved to the /root/sourcewnmp directory. During installation, existing software packages are detected and extracted directly for installation, eliminating the need for re-downloading.

v1.16 The official PHP PECL extension installer is no longer maintained. C-based PHP extensions are now installed using the pie extension installer.The complete list of available pie extensions can be found at:https://packagist.org/extensions

v1.15 Removed the default function. Let's Encrypt IP certificates are automatically issued by default, with NGINX BASIC AUTH enabled for additional security. The database is accessible directly at https://[ip]/phpmyadmin.

v1.13 introduces further kernel parameter tuning to enhance system concurrency.

v1.12 Added support for MariaDB 11.8.5 and optimized my.cnf with more reasonable default configurations.

v1.10 Modify SSH key logic: When multiple SSH keys are requested, only the latest public-private key pair remains valid. Older public keys are backed up and preserved.

v1.09 Delete the default site's .pem file to avoid confusion. The default site will only generate a .pem certificate file after formally applying for a certificate.

v1.05 Perform an overlay installation or execute `wnmp remariadb`. First, create a full database backup at: /home/all_databases_backup_[time].sql.gz

v1.04 Pure Cloud Storage Site Blocking.php File, Preventing Source Code Download

v1.03 Optimize Nginx parameters to accelerate SSL certificate validation

v1.02 Added --pcntl extension, compatible with workerman

v1.01 Supports the latest Swoole version, e.g.6.2.0-dev . Installed and deployed on PHP 8.5. The official website and PECL do not yet support deployment on PHP 8.5, but WNMP does.


---
## 🚀 Overview

**WNMP** installs Nginx, PHP, and MariaDB with a single command, configures SSL via `acme.sh`, sets up WebDAV, applies BBR/FQ tuning, and safely disables THP.

It’s designed for **small to medium websites, edge nodes, and private deployments**, providing a stable and reproducible runtime environment.

---

## ✨ Core Features

- **Ready-to-Use Web Runtime**  
  Compiles latest Nginx (1.29.5) with `dav-ext`, `http2`, and `stream` modules.  
  Supports PHP 8.2–8.5 and MariaDB 10.6 / 10.11 / 11.8.

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
cd /root && apt update && apt install -y curl
curl -fL https://wnmp.org/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

```bash
cd /root && apt update && apt install -y curl
curl -fL https://raw.githubusercontent.com/lowphpcom/wnmp/main/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

License: **GPLv3**  
Please execute commands using the root account on a completely clean system.

---

## 💡 Common Commands - Download and run bash wnmp.sh. The following commands can be executed from any directory.

| Purpose | Command |
|----------|----------|
| Normal Installation | `wnmp` |
| Check Status | `wnmp status` |
| SSH Key Login | `wnmp sshkey` |
| Add WebDAV Account | `wnmp webdav` |
| Create New Virtual Host (with SSL) | `wnmp vhost` |
| Kernel/Network Optimization Only | `wnmp tool` #Verification command: ulimit -n && ulimit -u && sysctl --system | 
| Restart All Services | `wnmp restart` |
| Cleanup | `wnmp remove` / `wnmp renginx` / `wnmp rephp` / `wnmp remariadb` |
| SSL Renewal | `wnmp sshcheck` / `wnmp sshtest`  |
---

## 🌐 Optional Footer Badge

```html
<small>This server is built by <a href="https://wnmp.org" target="_blank" rel="noopener">wnmp.org</a> one-click installer</small>
```

---
Does it support one-click generation of SSH login keys?
Yes. Run wnmp sshkey

=====================================================================

⚠️ Important reminder: Before confirming you have saved the private key to your own computer

⚠️ Do not disconnect the current SSH session, or you will be unable to log back into the server!

=====================================================================

Save the private key to your local computer. You can then load the key in an SSH client for password-less login.

After configuring key-based login, the server will block all username/password logins.
---

---

## ❓ Why doesn’t WNMP provide a control panel?
**Because the most secure server is the one without a control panel.**

GUI-based panels (such as BT Panel) make server management easier,  
but they also introduce serious security and performance trade-offs:

- 🔓 Extra open ports (e.g. 8888) increase the attack surface;  
- ⚠️ Password-based SSH login invites brute-force attacks;  
- 🧩 Persistent daemons may lead to privilege escalation risks;  
- 🔄 Auto-updates and plugin systems reduce auditability.

**WNMP takes a completely different philosophy:**

- ✅ **SSH key-only authentication by default** — the industry’s most secure method;  
- ✅ **No web panel ports**, no long-running background processes;  
- ✅ **Fully transparent, scriptable, and version-controllable system**;  
- ✅ **Focus on host-level performance and security baseline**, not GUI convenience.

WNMP is not a replacement for BT Panel —  
it’s an **engineer-oriented deployment template** designed for transparency, control, and maximum security.  
**In WNMP, the command line *is* your control panel.**

> Panels trade security for convenience — WNMP restores control and trust.

## How to Install and Use WNMP on Windows?

Ensure you are using Windows 11. First, install the WSL subsystem.

Press Win+R to open the Run dialog, type `cmd`. Press Shift+Ctrl+Enter to open the Administrator Command Prompt.

`wsl -l -o` # to check if remote system lists are accessible. If successful, WSL is functioning properly.

`wsl --install debian` # or `wsl --install debian --web-download` # (Begin installing the Debian 13 subsystem. The first command execution may require a system restart or prompt for missing CPU virtualization support. Follow the on-screen instructions.)

After successful installation, you will be prompted to configure a standard account and password. Once configured, simply type: exit to exit the subsystem.

`wsl -d debian -u root` # Log into the Debian system as root

```bash
cd /root && apt update && apt install -y curl
curl -fL https://wnmp.org/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

```bash
cd /root && apt update && apt install -y curl
curl -fL https://raw.githubusercontent.com/lowphpcom/wnmp/main/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

In the taskbar, navigate to and open:
`C:\Users\[username]\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`
Replace [username] with your actual Windows login username

Create a new wsl.vbs file and add the following content:
```bash
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -d debian", 0
' (ws.run "wsl -d ubuntu", 0)
```
After initialization completes, the subsystem will have the SSH server installed. Restart your computer as prompted, then you can log into your WSL Debian subsystem using an SSH client just like a regular server VPS.

Login address: 127.0.0.1 Port: 22

Additional WSL commands: In the Windows cmd environment (not the subsystem shell console):

`wsl -l -v` # View list of installed systems
`wsl --shutdown` # Stop the subsystem
`wsl --unregister debian` # Unregister the subsystem

To enable LAN access to the subsystem, navigate to the `C:\Users\[username]` directory. Replace [username] with your actual Windows login name.

Create a new .wslconfig file and add the following content:
```bash
[wsl2]
networkingMode=Mirrored
dnsTunneling=true
firewall=true
autoProxy=true
[experimental]
hostAddressLoopback=true
```
Run the following command in an administrator PowerShell window to configure Hyper-V firewall settings for inbound connections:

`Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow`

Restart your computer again. You can now log into the subsystem using the same LAN IP address as your local Windows system. Enter `ipconfig` in the cmd console to view your local LAN IP.

After restarting the computer, use an SSH client tool to access the subsystem and directly execute wnmp to begin deploying the web environment.

## 📖 License

Released under the **GNU General Public License v3.0 (GPLv3)**  
You may use, modify, and redistribute under the same license terms.

---

---

This project targets controlled environments and experienced users, and intentionally performs system- and kernel-level tuning.
Users who are not comfortable with these design decisions are advised not to use this project.
The issue tracker is reserved for reproducible functional bugs only.

---



## 🤝 Community

- **Official Site:** [https://wnmp.org](https://wnmp.org)
- **QQ Group:** 1075305476  
- **Telegram:** [t.me/wnmps](https://t.me/wnmps)
- **License:** [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
