# 🌀 WNMP 一键安装包-完整教程见官网[wnmp.org](https://wnmp.org/zh.html)
**Windows11(WSL)+Linux(Debian,Ubuntu) · Nginx · Mariadb(Mroonga) · PHP · WebDAV · 内核调优**

![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13%20%7C%20Ubuntu%2022--25-green.svg)
![Build](https://img.shields.io/badge/Installer-一键安装-orange.svg)



## wnmp.org一键web环境安装包，已得到mroonga搜索引擎官方认可，已在官方页面得到友情链接。
https://mroonga.org/users/


> 轻量 · 稳定 · 可复制  
> 一条命令在Windows11(WSL)+Linux(Debian,Ubuntu)安装 Nginx + PHP + MariaDB（内置 Mroonga 搜索引擎）+ WebDAV，自动完成内核/网络调优与 SSL 证书配置。

---

## WNMP：

## 1、Windows11(WSL)+Nginx+Mariadb(Mroonga)+PHP
(Windows11-WSL运行的Linux子系统部署，不是exe环境包)
## 2、(Linux)WebDav+Nginx+Mariadb(Mroonga)+PHP

## WNMP 的核心目标
WNMP 并不是“把 Nginx + PHP + MariaDB 打成容器”，而是为了在干净的系统环境下，一键完成 宿主级性能调优与安全基线配置（内核网络参数、ulimit 限制、SSH 密钥配置、编译优化等）。

## 为什么不适配 Docker
这些宿主级能力在容器内往往不可控，或需要 --privileged 等高权限运行，反而削弱了容器的隔离初衷。

## 推荐部署方式
因此，WNMP 推荐在 KVM 虚拟机、云服务器，或 Proxmox (PVE) 中开设的 KVM 虚拟系统上使用，以充分发挥其性能调优与系统优化的优势。


## 更新记录

v1.28 加入全局变量 wnmp 所有指令在任意目录可执行

v1.26 php开启fileinfo,soap,sodium内置组件支持

v1.21 优化中国大陆网络下载软件安装包网络不稳定掉线问题

v1.20 所有软件下载到/root/sourcewnmp目录，覆盖安装检测存在软件压缩包直接解压安装，不再重新下载

v1.16 PHP官方已停止维护pecl扩展安装器，改用pie扩展安装器安装C语言扩展。pie完整扩展列表：https://packagist.org/extensions

v1.15 取消default函数，已默认申请Let's Encrypt IP证书保护，并生成NGINX BASIC AUTH 加固保护；可直接https://[ip]/phpmyadmin 访问数据库

v1.13 进一步优化内核参数提高系统并发能力

v1.12 新增Mariadb 11.8.5 支持，优化my.cnf 更合理的默认配置

v1.10 修改sshkey代码逻辑，重复申请ssh密钥只允许最新公钥密钥对有效，旧公钥备份保存

v1.09 删除默认站点.pem文件，避免误会。默认站点正式申请证书后才会生成.pem证书文件

v1.05 覆盖安装或执行wnmp remariadb 先全库备份在：/home/all_databases_backup_[time].sql.gz

v1.04 纯网盘站点屏蔽.php文件,防止被下载源代码

v1.03 优化Nginx参数以加速SSL证书验证

v1.02 加入--pcntl扩展，兼容workerman

v1.01 支持swoole最新版本 例如6.2.0-dev 安装部署在PHP8.5，官网和pecl还不支持部署在php8.5,但wnmp支持





## 🚀 概述

**WNMP** 通过一条命令安装 Nginx、PHP、MariaDB，集成 `acme.sh` 自动申请证书，配置 WebDAV、开启 BBR/FQ、关闭 THP，为中小网站、边缘节点、私有化项目提供开箱即用的生产环境。

---

## ✨ 核心特性

- **即装即用的 Web 运行环境**  
  编译安装 Nginx 1.28.1（含 dav-ext/http2/stream 模块），支持 PHP 8.2–8.5 与 MariaDB 10.6 / 10.11 / 11.8。

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

请在完全干净的系统中使用root账号执行。  
脚本协议：**GPLv3**。

---

## 💡 常用命令-下载执行过bash wnmp.sh 以下指令可在任意目录执行

| 功能 | 命令 |
|------|------|
| 正常安装 | `wnmp` |
| 查看状态 | `wnmp status` |
| SSH 密钥登录 | `wnmp sshkey` |
| 添加 WebDAV 账号 | `wnmp webdav` |
| 创建虚拟主机（含证书） | `wnmp vhost` |
| 仅执行内核/网络调优 | `wnmp tool` # 验证指令： ulimit -n && ulimit -u && sysctl --system |
| 重启所有服务 | `wnmp restart` |
| 清理 | `wnmp remove` / `wnmp renginx` / `wnmp rephp` / `wnmp remariadb` |
---

## 🌐 可选页脚标识

```html
<small>本服务器由 <a href="https://wnmp.org" target="_blank" rel="noopener">wnmp.org</a> 一键包构建</small>
```
---
是否支持一键生成SSH登录密钥？
可以的。执行wnmp sshkey

=====================================================================

⚠️ 强提醒：在你确认【已把私钥保存到你自己的电脑】之前

⚠️ 请不要断开当前 SSH 会话，否则你将无法再次登录服务器！

=====================================================================

保存私钥到本地电脑，可以使用SSH客户端载入密钥免密码登录

配置密钥登录后，服务器将禁止一切账号密码登录
---

## ❓ 为什么 WNMP 不提供面板？
**因为最安全的服务器，是没有面板的那一台。**

面板类软件（例如 BT 宝塔）以图形化方式管理服务器，虽然方便，但同时也带来了：
- 🔓 开放额外端口（如 8888），扩大攻击面；
- ⚠️ 保留 SSH 密码登录，增加暴力破解风险；
- 🧩 长期常驻的面板守护进程，可能被提权或注入；
- 🔄 自动更新与插件系统，降低可审计性。

而 **WNMP 的设计理念完全不同**：

- ✅ **默认启用 SSH 密钥登录**（最安全的登录方式）；  
- ✅ **不开放任何 Web 面板端口**，部署完成后几乎零常驻进程；  
- ✅ **系统配置完全透明，可脚本化、可版本化、可审计**；  
- ✅ **追求宿主级性能与安全基线**，而非图形界面的便利。

WNMP 的目标不是“替代宝塔”，而是提供一份**面向工程师的纯净环境模板**——  
**命令行即控制面板，安全性与可控性永远优先。**
> 面板适合入门者；WNMP 属于工程师。
---




## Win系统如何安装使用WNMP？

确认你是win11系统。首先需要安装wsl子系统

Win+R 组合键打开运行输入框，输入cmd # 键盘组合键shift+ctrl+enter 进入管理员模式控制台。

wsl -l -o # 查看是否能读取远程系统列表，如果能正常读取，表示wsl正常

`wsl --install debian` # 或者 `wsl --install debian --web-download` # (开始安装debian13子系统，第一次执行命令会要求重启电脑，或提示未开启CPU虚拟化支持等，请根据提示操作)

正常安装后会要求配置一个普通账号+密码，配置成功后直接：exit 退出子系统


`wsl -d debian -u root` # 以root账号身份登录debian系统

以Debian13为例，中国大陆需要切换系统更新源
```bash
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian/ trixie main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security/ trixie-security main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ trixie-backports main contrib non-free non-free-firmware
EOF
```

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

在此电脑任务地址栏定位打开C:\Users\[username]\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup # 请用windows登录的真实账号名代替[username]

新建一个wsl.vbs文件并写入内容：
```bash
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -d debian", 0
#(ws.run "wsl -d ubuntu", 0)
```
初始化完成后，子系统已安装SSH服务端，根据提示重启电脑后，你可以像正常服务器VPS一样用SSH客户端登录你的wsl debian 子系统

登录地址:127.0.0.1 端口:22

更多wsl命令：在windows cmd环境下，非子系统shell控制台

`wsl -l -v` # 查看已安装系统列表

`wsl --shutdown` # 停止子系统

`wsl --unregister debian` # 卸载子系统

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

`Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow`

再次重启电脑。现在你可以登录与你本机win系统相同局域网IP地址登录子系统。请在cmd命令控制台输入ipconfig 查看你的本机局域网IP

重启电脑后，用ssh客户端工具进入子系统直接执行 wnmp 开始部署web环境

---

## 📖 开源协议

本项目以 **GNU GPLv3** 协议开源，允许在相同协议下使用、修改与再发布。

---

---

本项目面向可控环境与高级用户，包含对系统与内核的主动调优。
若你不接受该设计取向，请勿使用本项目。
Issues 仅用于提交可复现的功能性 BUG。

---


## 🤝 社区

- **官网:** [https://wnmp.org](https://wnmp.org)
- **QQ群:** 1075305476  
- **Telegram:** [t.me/wnmps](https://t.me/wnmps)
- **License:** [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
