# 🐚 shell

自用的 Linux Shell 工具集合，用于软件部署、服务配置与日常运维。各工具独立使用，运行环境、参数和使用方法见对应章节。

## 🧰 工具目录

| 工具 | 脚本 | 用途 | 使用说明 |
| --- | --- | --- | --- |
| Hev SOCKS5 Server | [`hev-socks5-install.sh`](./hev-socks5-install.sh) | 安装或替换 SOCKS5 服务，支持 TCP/UDP 和账号认证 | [查看教程](#hev-socks5-server) |

<a id="hev-socks5-server"></a>

## 🌐 Hev SOCKS5 Server

适用于使用 systemd 的 Debian / Ubuntu，支持 x86_64 和 ARM64。需要 root 权限和 curl；支持全新安装及替换已有安装。

🔄 重新执行安装命令会替换程序、覆盖配置并重启服务，同时设置开机自启。配置按本次参数或默认值重新生成，不沿用旧配置；省略账号密码时会重新随机生成，请保存新的连接信息。

### 交互配置

在终端执行以下命令，按提示依次输入端口、用户名、密码和 workers 线程数。每项提示都会显示默认值，直接按 Enter 即可采用。

```bash
curl -fsSL https://raw.githubusercontent.com/akiiya/shell/main/hev-socks5-install.sh | sudo bash
```

交互输入通过终端读取，因此管道安装也可以逐项配置。

### 带参数直接安装

只要传入任意配置参数，就不会交互询问；未指定的项自动使用默认值。以下示例包含全部配置参数，可按需修改或省略：

```bash
curl -fsSL https://raw.githubusercontent.com/akiiya/shell/main/hev-socks5-install.sh | sudo bash -s -- \
  --port     65127 \
  --username 'myuser' \
  --password 'YourStrongPassword' \
  --workers  5
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--port` | `65127` | TCP/UDP 共用此数字端口，范围 1–65535 |
| `--username` | 随机生成的 16 位十六进制账号 | 不允许空白字符，最多 255 字符；安装成功后显示 |
| `--password` | 随机生成的 32 位十六进制密码 | 不允许空白字符，最多 255 字符；自动生成时安装成功后会显示，请保存 |
| `--workers` | `5` | 工作线程数，可指定 1–256 |
| `-h` / `--help` | — | 查看帮助，不执行安装 |

🔐 命令行指定的密码可能保存在 shell 历史记录中或出现在进程列表中。可以省略 `--password` 使用随机密码，或使用交互模式输入密码（输入不回显）。

### 🛠️ 安装后管理

服务会立即启动并设置开机自启，默认监听 `0.0.0.0:65127`（TCP/UDP），允许代理端解析 IPv4 / IPv6 域名。配置和账号密码保存在 `/etc/hev-socks5-server/main.yml`，文件仅 root 可读写。

默认连接超时为 `10000` 毫秒，TCP 读写超时为 `300000` 毫秒，UDP 读写超时为 `60000` 毫秒，文件描述符上限为 `65535`。

```bash
# 查看服务状态
sudo systemctl status hev-socks5-server --no-pager

# 查看最近日志
sudo journalctl -u hev-socks5-server -n 50 --no-pager

# 修改配置后重启
sudo systemctl restart hev-socks5-server
```

请在服务器防火墙或云安全组同时放行所选 TCP 和 UDP 端口（默认均为 `65127`）。
