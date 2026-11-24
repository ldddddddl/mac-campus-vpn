# mac-campus-vpn

[![CI](https://github.com/ldddddddl/mac-campus-vpn/actions/workflows/ci.yml/badge.svg)](https://github.com/ldddddddl/mac-campus-vpn/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/Platform-macOS_(arm64%20%7C%20amd64)-lightgrey.svg)

> 在 macOS 上以**零 root、零驱动、零 Docker、零路由污染**的方式隔离运行高校 EasyConnect / aTrust 校园网 VPN：仅让校内 SSH 走校园网，与 **Clash Verge** 完全隔离互不干扰，并支持**校外走 VPN / 校内自动直连**无感切换。

本项目基于优秀的开源项目 [Mythologyli/zju-connect](https://github.com/Mythologyli/zju-connect)（AGPL-3.0）进行安全加固与 macOS 工程化封装，适用于任意使用深信服 **EasyConnect**（或 **aTrust**）的高校校园网。

---

## 核心特性与安全加固

相比直接安装官方 EasyConnect 客户端，或直接运行上游默认配置，本项目做了以下加固：

| 维度 | 做法 |
| :--- | :--- |
| **彻底隔离，不干扰 Clash Verge** | 依托 gVisor 用户态 TCP/IP 协议栈，不建系统 TUN 虚拟网卡、不改 macOS 路由表和 DNS、无需 `sudo`，与 Clash Verge（规则模式 / TUN 模式）天然零冲突。 |
| **严格 TLS 证书校验（默认开启）** | EasyConnect 登录、Token 获取与 L3 隧道握手默认开启标准 CA 证书与域名校验（`insecure_skip_verify = false`），堵死公共 Wi-Fi 登录阶段中间人风险；若个别高校使用自签名证书，可显式开启 `insecure_skip_verify = true`。 |
| **仅本机回环监听，最小暴露面** | 默认锁死 `socks_bind = "127.0.0.1:11080"` 并关闭未使用的 HTTP/DNS 代理（避免上游默认 `0.0.0.0:1080` / `:1081` 在公共 Wi-Fi 下被同局域网蹭网）。 |
| **屏蔽外部代理环境变量** | 源码层强制 `transport.Proxy = nil` 且启动脚本清除 `http_proxy` / `all_proxy`，防止 VPN 拨号误走 Clash 系统代理。 |
| **macOS 钥匙串（Keychain）托管凭据** | 配置文件**不保存密码**；账号密码由 macOS 系统钥匙串加密保存，运行时动态注入，不进 Shell 历史，不出现在 `ps` 参数中。 |
| **后台驻留 + 退出清日志** | 支持 `campus-vpn` 一键后台运行（可直接关终端）；执行 `campus-vpn stop` 时优雅退出并自动清空会话日志（`600` 权限，不残留 `TWFID` / `Token`）。 |
| **校内 / 校外 SSH 全自动切换** | 配合 OpenSSH 原生 `Match host ... exec`，开着 `campus-vpn` 自动走校园网隧道，退掉即自动切换为校内直连（兼容终端 SSH、SCP/RSync 与 VS Code / Cursor Remote-SSH）。 |

---

## 工作原理

```text
校内 SSH (ssh / VS Code Remote-SSH)
   │  OpenSSH 检测 127.0.0.1:11080 是否在监听：
   │  ├─ 在校外（已启动 campus-vpn）──▶ 经回环 127.0.0.1:11080 ──▶ zju-connect 用户态网络栈 ──▶ 学校 VPN 网关 ──▶ 校内服务器
   │  └─ 在校内（已停止 campus-vpn）──▶ 跳过 ProxyCommand ──────▶ 直接走当前校园网直连校内服务器
   │
其他所有流量（浏览器 / App / GitHub 等）
   └──▶ 100% 照常走 Clash Verge（完全互不干扰）
```

---

## 快速开始（3 步完成）

### 前置依赖
* macOS（Apple Silicon `arm64` 或 Intel `x86_64`）
* Go 1.25+（用于本地从源码编译，编译完即可删除 Go）：
  ```bash
  brew install go
  ```

### 第 1 步：本地编译安装

```bash
git clone https://github.com/ldddddddl/mac-campus-vpn.git
cd mac-campus-vpn
./install.sh
```

脚本会在本地纯 Go（`CGO_ENABLED=0`）编译加固版 `zju-connect`，并将 `zju-connect` 与 `campus-vpn` 安装到 `~/.local/bin/`（权限 `700`）。

### 第 2 步：初始化网关与钥匙串凭据（仅需一次）

打开新终端（或先执行 `source ~/.zprofile`）：

```bash
campus-vpn setup
```

按提示输入：
1. 学校 VPN 地址（如 `vpn.example.edu.cn`，直接粘贴 `https://...` 链接也可自动提取域名）；
2. 端口（默认 `443`）、协议（默认 `easyconnect`）；
3. 是否需要跳过自签名证书校验（正规高校 HTTPS 证书直接回车选默认 `N`）；
4. 校园网用户名与密码（密码直接加密存入 macOS 钥匙串，不落明文文件）。

### 第 3 步：在 `~/.ssh/config` 配置自动切换

先正常定义你的校内服务器，再在文件**末尾**加上 `Match host ... exec` 规则（把 `10.*,*.example.edu.cn` 替换为你学校服务器的实际网段或域名）：

```sshconfig
# 1. 正常写你的校内服务器（不要写 ProxyCommand）
Host lab-gpu
    HostName 10.xx.xx.xx
    User your_username
    Port 22

# 2. 【放在校内 Host 定义下方】自动探测本地 11080 端口
#    开着 campus-vpn -> 自动走校园网 SOCKS5
#    停掉 campus-vpn -> 自动跳过，走当前校园网直连
Match host 10.*,*.example.edu.cn exec "/usr/bin/nc -z 127.0.0.1 11080 >/dev/null 2>&1"
    ProxyCommand /usr/bin/nc -X 5 -x 127.0.0.1:11080 %h %p
```

> **提示**：如果你本机还有局域网/直连设备（如 `172.16.*` 或 `192.168.*`），请只把学校服务器所在的网段写进 `Match host`，避免误伤本地直连主机。

---

## 日常命令

```bash
campus-vpn          # 后台连接校园网（启动成功后可直接关掉终端）
campus-vpn stop     # 断开并清空会话日志（回到校内时运行，SSH 立即恢复直连）
campus-vpn status   # 查看当前是否运行及监听状态
campus-vpn logs     # 查看最近运行日志（排查连接问题）
campus-vpn fg       # 前台运行（学校需要图形/短信验证码交互时使用）
campus-vpn setup    # 重新配置网关或更新钥匙串密码
campus-vpn remove   # 从 macOS 钥匙串删除保存的凭据
./install.sh --uninstall  # 卸载二进制与脚本
```

---

## 与 Clash Verge 共存说明

* **规则模式（推荐）**：绝大多数规则集默认将 `.cn` / `.edu.cn` 与 `10.0.0.0/8` 设为 `DIRECT`，通常**无需额外配置**。
* **如何自检**：连上 `campus-vpn` 后，打开 Clash Verge 的 **连接（Connections）** 搜索学校 VPN 域名，确认链路显示 **`DIRECT`** 即可。
* 如果你的自定义规则集把学校 VPN 域名代理到了海外节点，在 Clash Verge 规则覆写顶部加上这两条即可：
  ```yaml
  - PROCESS-NAME,zju-connect,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  ```

---

## 常见问题

* **连学校 VPN 时报 `x509: certificate signed by unknown authority`**：
  说明你们学校 VPN 网关使用了自签名证书。重新运行 `campus-vpn setup` 并在证书校验提示时选 `y`（或手动将 `~/.config/campus-vpn/config.toml` 中的 `insecure_skip_verify` 改为 `true`）。
* **学校登录需要图形验证码或短信验证码**：
  先运行 `campus-vpn fg` 在前台完成一次交互验证。
* **曾安装过官方 EasyConnect**：
  建议在确认本方案稳定后卸载官方客户端，避免其 `root` 权限的 `EasyMonitor` / `ECAgent` 后台守护进程常驻占用资源或干扰网络。

---

## 致谢与协议

* 本项目核心协议与用户态网络栈源自 [Mythologyli/zju-connect](https://github.com/Mythologyli/zju-connect)（上游完整文档见 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)），最初协议逆向源自 [lyc8503/EasierConnect](https://github.com/lyc8503/EasierConnect)。
* 本仓库遵循上游 **GNU Affero General Public License v3.0 (AGPL-3.0)**，完整协议文本见 [LICENSE](LICENSE)。
