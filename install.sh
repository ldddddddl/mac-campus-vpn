#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/campus-vpn"
STATE_DIR="$HOME/.local/state/campus-vpn"
ZPROFILE="$HOME/.zprofile"

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -x "$BIN_DIR/campus-vpn" ]]; then
    "$BIN_DIR/campus-vpn" stop || true
    "$BIN_DIR/campus-vpn" remove || true
  fi
  rm -f "$BIN_DIR/campus-vpn" "$BIN_DIR/zju-connect"
  rm -rf "$STATE_DIR"
  echo "已卸载 campus-vpn 与 zju-connect（配置文件 ${CONFIG_DIR} 与 ~/.ssh/config 请按需手动清理）。"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "此安装脚本针对 macOS（依赖 macOS 钥匙串与系统 /usr/bin/nc）。" >&2
  echo "Linux/Windows 可直接使用 go build . 单独编译 zju-connect。" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "未检测到 Go 工具链，请先安装 Go（例如: brew install go）。" >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) GOARCH="arm64" ;;
  x86_64) GOARCH="amd64" ;;
  *)
    echo "不支持的架构: ${ARCH}" >&2
    exit 1
    ;;
esac

VERSION="hardened"
if command -v git >/dev/null 2>&1 && git -C "$REPO_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
  VERSION="$(git -C "$REPO_DIR" rev-parse --short HEAD)-hardened"
fi

echo "==> 正在本地编译安全加固版 zju-connect (darwin/${GOARCH})..."
umask 077
mkdir -p "$BIN_DIR" "$CONFIG_DIR"

(
  cd "$REPO_DIR"
  CGO_ENABLED=0 GOOS=darwin GOARCH="$GOARCH" \
    go build -trimpath -ldflags "-s -w -X main.zjuConnectVersion=${VERSION}" \
    -o "$BIN_DIR/zju-connect" .
)

install -m 700 "$REPO_DIR/scripts/campus-vpn" "$BIN_DIR/campus-vpn"
chmod 700 "$BIN_DIR/zju-connect" "$BIN_DIR" "$CONFIG_DIR"

if [[ ! -f "$ZPROFILE" ]] || ! grep -Fq '.local/bin' "$ZPROFILE"; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$ZPROFILE"
  echo "==> 已将 ~/.local/bin 写入 ${ZPROFILE}"
fi

cat <<'EOF'

✅ 安装完成！接下来只需 2 步：

1. 打开新终端（或先执行 source ~/.zprofile），运行一次性初始化向导（密码存入 macOS 钥匙串，不落明文）：
   campus-vpn setup

2. 在 ~/.ssh/config 末尾添加自动切换规则（把 10.*,*.example.edu.cn 换成你们学校的网段/域名）：

   Match host 10.*,*.example.edu.cn exec "/usr/bin/nc -z 127.0.0.1 11080 >/dev/null 2>&1"
       ProxyCommand /usr/bin/nc -X 5 -x 127.0.0.1:11080 %h %p

日常使用：
  - 校外连接（后台运行，可直接关终端）：campus-vpn
  - 回校断开（自动恢复校内直连 SSH）  ：campus-vpn stop
  - 查看运行状态 / 日志               ：campus-vpn status / campus-vpn logs
EOF
