#!/usr/bin/env bash
set -Eeuo pipefail

# hev-socks5-server 原生一键安装（Debian/Ubuntu + systemd）
# 用法：sudo bash hev-socks5-install.sh --port 1080 --username myuser --workers 4
# 不传参数时逐项交互配置；传参时未指定的配置使用默认值。

BIN=/usr/local/bin/hev-socks5-server
CONF_DIR=/etc/hev-socks5-server
CONF="$CONF_DIR/main.yml"
UNIT=/etc/systemd/system/hev-socks5-server.service
INTERACTIVE=0
(($#)) || INTERACTIVE=1
PORT=65127
USERNAME=''
USERNAME_SPECIFIED=0
PASSWORD=''
PASSWORD_SPECIFIED=0
WORKERS=5

usage() {
  cat <<'HELP'
用法：sudo bash hev-socks5-install.sh [--port 端口] [--username 用户名] [--password 密码] [--workers 线程数]
不传参数：进入终端交互配置，逐项输入，按 Enter 使用提示中的默认值。
传入配置参数：直接安装，未指定的配置使用默认值，不再交互询问。
默认值：TCP/UDP 端口 65127，workers 为 5，账号随机生成 16 位，密码随机生成 32 位。
注意：--password 的值可能被进程列表或 shell 历史记录保存。
支持全新安装和替换安装；重新执行会覆盖旧配置并重启服务。
替换安装时仍按本次参数或默认值配置，不沿用旧账号密码。
HELP
}

while (($#)); do
  case "$1" in
    --port|--username|--password|--workers)
      (($# >= 2)) || { echo "缺少参数值: $1" >&2; exit 1; }
      [[ "$2" != --* ]] || { echo "缺少参数值: $1" >&2; exit 1; }
      case "$1" in
        --port) PORT="$2" ;;
        --username) USERNAME="$2"; USERNAME_SPECIFIED=1 ;;
        --password) PASSWORD="$2"; PASSWORD_SPECIFIED=1 ;;
        --workers) WORKERS="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "$EUID" -eq 0 ]] || { echo '请以 root 身份运行（sudo bash ...）' >&2; exit 1; }
command -v systemctl >/dev/null || { echo '需要 systemd' >&2; exit 1; }
command -v curl >/dev/null || { echo '需要 curl，请先安装：apt-get install -y curl' >&2; exit 1; }
for path in "$BIN" "$CONF" "$UNIT"; do
  if [[ -e "$path" ]]; then
    echo '检测到已有安装，将替换程序、覆盖配置并重启服务。'
    break
  fi
done

case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "暂不支持的 CPU 架构: $(uname -m)" >&2; exit 1 ;;
esac

# 显式传入空账号或密码时留给校验报错；只有省略时才生成默认值。
GENERATED_PASSWORD=0
if [[ "$INTERACTIVE" -eq 1 ]]; then
  exec 3<> /dev/tty || { echo '交互配置需要终端；自动安装请传入配置参数（参见 --help）' >&2; exit 1; }
fi
if [[ "$USERNAME_SPECIFIED" -eq 0 ]]; then
  USERNAME="$(od -An -N8 -tx1 /dev/urandom | tr -d '[:space:]')"
fi
if [[ "$PASSWORD_SPECIFIED" -eq 0 ]]; then
  PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d '[:space:]')"
  GENERATED_PASSWORD=1
fi
if [[ "$INTERACTIVE" -eq 1 ]]; then
  echo 'SOCKS5 交互配置（按 Enter 使用显示的默认值）' >&3
  read -r -u 3 -p "SOCKS5 监听端口 [默认: $PORT]: " INPUT
  PORT="${INPUT:-$PORT}"
  read -r -u 3 -p "SOCKS5 用户名 [默认: $USERNAME]: " INPUT
  USERNAME="${INPUT:-$USERNAME}"
  read -r -s -u 3 -p "SOCKS5 密码（输入不回显）[默认: $PASSWORD]: " INPUT
  printf '\n' >&3
  if [[ -n "$INPUT" ]]; then
    PASSWORD="$INPUT"
    GENERATED_PASSWORD=0
  fi
  unset INPUT
  read -r -u 3 -p "SOCKS5 workers 线程数 [默认: $WORKERS]: " INPUT
  WORKERS="${INPUT:-$WORKERS}"
  unset INPUT
  exec 3>&-
fi
if [[ ! "$PORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
  echo '端口必须在 1~65535 之间' >&2; exit 1;
fi
PORT=$((10#$PORT))
if [[ ! "$WORKERS" =~ ^[0-9]{1,3}$ ]] || (( 10#$WORKERS < 1 || 10#$WORKERS > 256 )); then
  echo 'workers 必须在 1~256 之间' >&2; exit 1;
fi
WORKERS=$((10#$WORKERS))
# 保留账号密码的非空、无空白及长度校验。
[[ -n "$USERNAME" && "${#USERNAME}" -le 255 && "$USERNAME" != *[[:space:]]* ]] || {
  echo '用户名不能为空、不能包含空白字符且不能超过 255 字符' >&2; exit 1;
}
[[ -n "$PASSWORD" && "${#PASSWORD}" -le 255 && "$PASSWORD" != *[[:space:]]* ]] || {
  echo '密码不能为空、不能包含空白字符且不能超过 255 字符' >&2; exit 1;
}

TMPDIR_INSTALL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_INSTALL"; unset PASSWORD' EXIT
URL="https://github.com/heiher/hev-socks5-server/releases/latest/download/hev-socks5-server-linux-${ARCH}"
echo "下载官方 Linux ${ARCH} Release..."
curl --fail --location --show-error --silent --retry 3 --output "$TMPDIR_INSTALL/hev-socks5-server" "$URL"
[[ -s "$TMPDIR_INSTALL/hev-socks5-server" ]] || { echo '下载失败：文件为空' >&2; exit 1; }

install -d -m 700 "$CONF_DIR"
install -m 755 "$TMPDIR_INSTALL/hev-socks5-server" "$BIN"
# YAML 单引号字符串通过重复单引号转义，保留用户输入的特殊字符。
USERNAME_YAML="${USERNAME//\'/\'\'}"
PASSWORD_YAML="${PASSWORD//\'/\'\'}"

( umask 077
cat > "$CONF" <<CONFIG
main:
  workers: $WORKERS
  port: $PORT
  listen-address: '0.0.0.0'
  udp-port: $PORT
  udp-listen-address: '0.0.0.0'
  domain-address-type: unspec
auth:
  username: '$USERNAME_YAML'
  password: '$PASSWORD_YAML'
misc:
  limit-nofile: 65535
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
  log-file: stderr
  log-level: warn
CONFIG
)
unset USERNAME_YAML PASSWORD_YAML
chmod 600 "$CONF"

cat > "$UNIT" <<UNITFILE
[Unit]
Description=Hev SOCKS5 Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=$BIN $CONF
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNITFILE
chmod 644 "$UNIT"
systemctl daemon-reload
if ! systemctl enable hev-socks5-server; then
  echo '设置开机自启失败，请检查 systemd 服务配置' >&2
  exit 1
fi
# restart 对未运行的服务也会启动，确保替换安装后加载新程序和配置。
if ! systemctl restart hev-socks5-server; then
  echo '启动或重启失败，请检查：journalctl -u hev-socks5-server -n 50 --no-pager' >&2
  exit 1
fi
systemctl is-active --quiet hev-socks5-server || {
  echo '服务未保持运行，请检查日志' >&2; exit 1;
}
systemctl is-enabled --quiet hev-socks5-server || {
  echo '服务未设置为开机自启，请检查 systemd 服务配置' >&2; exit 1;
}

echo "安装完成：监听 TCP/UDP ${PORT}，用户名 ${USERNAME}，workers=${WORKERS}。"
if [[ "$GENERATED_PASSWORD" -eq 1 ]]; then
  printf '随机生成的 SOCKS5 密码：%s\n请妥善保存。\n' "$PASSWORD"
fi
unset PASSWORD
echo "已开机自启。检查状态：systemctl status hev-socks5-server --no-pager"
echo "提示：请在防火墙和安全组中放行 TCP/UDP ${PORT}。"
