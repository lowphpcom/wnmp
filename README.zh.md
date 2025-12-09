# 🌀 WNMP 一键安装包
**Windows11(WSL)+Linux(Debian,Ubuntu) · Nginx · Mariadb(Mroonga) · PHP · WebDAV · 内核调优**

![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13%20%7C%20Ubuntu%2022--25-green.svg)
![Build](https://img.shields.io/badge/Installer-一键安装-orange.svg)

> 轻量 · 稳定 · 可复制  
> 一条命令在Windows11(WSL)+Linux(Debian,Ubuntu)安装 Nginx + PHP + MariaDB（内置 Mroonga 搜索引擎）+ WebDAV，自动完成内核/网络调优与 SSL 证书配置。

---

## WNMP：

## 1、Windows11(WSL)+Nginx+Mariadb(Mroonga)+PHP

## 2、(Linux)WebDav+Nginx+Mariadb(Mroonga)+PHP

## WNMP 的核心目标
WNMP 并不是“把 Nginx + PHP + MariaDB 打成容器”，而是为了在干净的系统环境下，一键完成 宿主级性能调优与安全基线配置（内核网络参数、ulimit 限制、SSH 密钥配置、编译优化等）。

## 为什么不适配 Docker
这些宿主级能力在容器内往往不可控，或需要 --privileged 等高权限运行，反而削弱了容器的隔离初衷。

## 推荐部署方式
因此，WNMP 推荐在 KVM 虚拟机、云服务器，或 Proxmox (PVE) 中开设的 KVM 虚拟系统上使用，以充分发挥其性能调优与系统优化的优势。


## 🚀 概述

**WNMP** 通过一条命令安装 Nginx、PHP、MariaDB，集成 `acme.sh` 自动申请证书，配置 WebDAV、开启 BBR/FQ、关闭 THP，为中小网站、边缘节点、私有化项目提供开箱即用的生产环境。

---

## ✨ 核心特性

- **即装即用的 Web 运行环境**  
  编译安装 Nginx 1.28.0（含 dav-ext/http2/stream 模块），支持 PHP 8.2–8.5 与 MariaDB 10.6 / 10.11。

- **内核 / 网络调优**  
  启用 BBR/FQ，优化 `somaxconn` 与文件句柄，关闭 THP，自动写入 sysctl 与 limits。

- **证书自动化**  
  集成 `acme.sh`，优先使用 Cloudflare DNS-01，失败时自动回落 webroot，签发后自动 reload Nginx。

- **多站点与 WebDAV 支持**  
  一键创建虚拟主机，内置 phpMyAdmin 保护与 WebDAV 账号管理，每个域名独立密码文件 `/home/passwd/`。

- **可维护的目录结构**
  ```
  /usr/local/nginx
  /usr/local/php
  /home/wwwroot
  ```

- **安全默认值**
  禁用隐蔽目录与危险后缀，合理的超时与缓存配置，关闭不必要的 PHP 选项。

---

## ⚙️ 安装方法

```bash
apt install -y curl
curl -fL https://wnmp.org/zh/wnmp.sh -o wnmp.sh
chmod +x wnmp.sh
bash wnmp.sh
```

请在完全干净的系统中使用root账号执行。  
脚本协议：**GPLv3**。

---

## 💡 常用命令

| 功能 | 命令 |
|------|------|
| 正常安装 | `bash wnmp.sh` |
| 查看状态 | `bash wnmp.sh status` |
| SSH 密钥登录 | `bash wnmp.sh sshkey` |
| 添加 WebDAV 账号 | `bash wnmp.sh webdav` |
| 默认站点域名与证书 | `bash wnmp.sh default` |
| 创建虚拟主机（含证书） | `bash wnmp.sh vhost` |
| 仅执行内核/网络调优 | `bash wnmp.sh tool` |
| 重启所有服务 | `bash wnmp.sh restart` |
| 清理 | `bash wnmp.sh remove` / `bash wnmp.sh renginx` / `bash wnmp.sh rephp` / `bash wnmp.sh remariadb` |
| WSL初始化 | `bash wnmp.sh wslinit` |
---

## 🌐 可选页脚标识

```html
<small>本服务器由 <a href="https://wnmp.org" target="_blank" rel="noopener">wnmp.org</a> 一键包构建</small>
```
---
是否支持一键生成SSH登录密钥？
可以的。执行bash wnmp.sh sshkey

=====================================================================

⚠️ 强提醒：在你确认【已把私钥保存到你自己的电脑】之前

⚠️ 请不要断开当前 SSH 会话，否则你将无法再次登录服务器！

=====================================================================

保存私钥到本地电脑，可以使用SSH客户端载入密钥免密码登录

配置密钥登录后，服务器将禁止一切账号密码登录
---


## Win系统如何安装使用WMMP？

确认你是win11系统。首先需要安装wsl子系统

Win+R 组合键打开运行输入框，输入cmd # 键盘组合键shift+ctrl+enter 进入管理员模式控制台。

输入:wsl -l -o # 查看是否能读取远程系统列表，如果能正常读取，表示wsl正常

输入:wsl --install debian # (开始安装debian13子系统，第一次执行命令会要求重启电脑，或提示未开启CPU虚拟化支持等，请根据提示操作)

正常安装后会要求配置一个普通账号+密码，配置成功后直接：exit 退出子系统

wsl -d debian -u root # 以root账号身份登录debian系统
```bash
cd ~
apt update && apt install -y curl && curl -fL https://wnmp.org/zh/wnmp.sh -o wnmp.sh && chmod +x wnmp.sh && bash wnmp.sh wslinit
```
在此电脑任务地址栏定位打开C:\Users\[username]\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup # 请用windows登录的真实账号名代替[username]

新建一个wsl.vbs文件并写入内容：
```bash
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -d debian", 0
```
初始化完成后，子系统已安装SSH服务端，根据提示重启电脑后，你可以像正常服务器VPS一样用SSH客户端登录你的wsl debian 子系统

登录地址:127.0.0.1 端口:22

更多wsl命令：在windows cmd环境下，非子系统shell控制台

wsl -l -v # 查看已安装系统列表

wsl --shutdown # 停止子系统

wsl --unregister # 卸载子系统

如需要局域网访问子系统，打开C:\Users\[username]目录 # 请用windows登录的真实账号名代替[username]

新建一个.wslconfig文件并写入内容：
```bash
[wsl2]
networkingMode=Mirrored
dnsTunneling=true
firewall=true
autoProxy=true
[experimental]
hostAddressLoopback=true
```
在管理员权限 PowerShell 窗口中运行以下命令,以配置 Hyper-V 防火墙 设置以允许入站连接：

Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow

再次重启电脑。现在你可以登录与你本机win系统相同局域网IP地址登录子系统。请在cmd命令控制台输入ipconfig 查看你的本机局域网IP

---

## 📖 开源协议

本项目以 **GNU GPLv3** 协议开源，允许在相同协议下使用、修改与再发布。

---

## 🤝 社区

- **官网:** [https://wnmp.org](https://wnmp.org)
- **QQ群:** 1075305476  
- **Telegram:** [t.me/wnmps](https://t.me/wnmps)
- **License:** [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
