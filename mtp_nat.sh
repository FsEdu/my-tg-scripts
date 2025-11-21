#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

MTG_BIN="/usr/local/bin/mtg"
MTG_CONF="/usr/local/etc/mtg.toml"
MTG_SERVICE="/etc/systemd/system/mtg.service"

info()  { echo -e "[${green}信息${plain}] $*"; }
warn()  { echo -e "[${yellow}提示${plain}] $*"; }
error() { echo -e "[${red}错误${plain}] $*"; }

check_root() {
  if [ "$(id -u)" != "0" ]; then
    error "请用 root 运行（或 sudo -i 切到 root）。"
    exit 1
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      debian|ubuntu)
        OS="debian"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        ;;
      centos|rocky|almalinux)
        OS="centos"
        PKG_UPDATE="yum makecache -y"
        PKG_INSTALL="yum install -y"
        ;;
      alpine)
        OS="alpine"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add --no-cache"
        ;;
      *)
        warn "无法识别系统 ID=$ID，默认按 Debian/Ubuntu 处理。"
        OS="debian"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        ;;
    esac
  else
    warn "找不到 /etc/os-release，默认按 Debian/Ubuntu 处理。"
    OS="debian"
    PKG_UPDATE="apt-get update -y"
    PKG_INSTALL="apt-get install -y"
  fi
  info "检测到系统类型：$OS"
}

install_deps() {
  info "更新软件源..."
  eval "$PKG_UPDATE" >/dev/null 2>&1 || warn "更新软件源失败，继续尝试安装依赖。"

  info "安装依赖：curl wget tar ca-certificates..."
  case "$OS" in
    debian|centos)
      eval "$PKG_INSTALL curl wget tar ca-certificates" || {
        error "安装依赖失败，请检查网络和软件源。"
        exit 1
      }
      ;;
    alpine)
      eval "$PKG_INSTALL curl wget tar ca-certificates" || {
        error "安装依赖失败，请检查网络和软件源。"
        exit 1
      }
      ;;
  esac
}

detect_arch() {
  local u
  u=$(uname -m)
  case "$u" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    i386|i686)
      ARCH="386"
      ;;
    *)
      error "暂不支持的架构：$u"
      exit 1
      ;;
  esac
  info "检测到架构：$ARCH"
}

download_mtg() {
  if [ -x "$MTG_BIN" ]; then
    info "检测到已存在 $MTG_BIN，将覆盖为最新版本。"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    error "未找到 curl，请先安装 curl。"
    exit 1
  fi

  info "从 GitHub 获取 mtg 最新版本号..."
  local tag
  tag=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest \
        | grep '"tag_name"' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')

  if [ -z "$tag" ]; then
    error "获取 mtg 最新版本失败，可能是 GitHub API 频率受限或网络问题。"
    exit 1
  fi

  local ver file url tmpdir
  ver="${tag#v}"
  file="mtg-${ver}-linux-${ARCH}.tar.gz"
  url="https://github.com/9seconds/mtg/releases/download/${tag}/${file}"

  info "最新版本：${tag}，下载文件：${file}"
  tmpdir=$(mktemp -d)
  cd "$tmpdir" || exit 1

  info "开始下载 mtg 二进制..."
  if ! curl -fL -o "$file" "$url"; then
    error "下载 $url 失败。"
    rm -rf "$tmpdir"
    exit 1
  fi

  if ! tar -xzf "$file"; then
    error "解压 $file 失败。"
    rm -rf "$tmpdir"
    exit 1
  fi

  # 解压后目录名一般是 mtg-${ver}-linux-${ARCH}
  local dir
  dir=$(find . -maxdepth 1 -type d -name "mtg-*-linux-*")
  if [ ! -x "$dir/mtg" ]; then
    error "在解压目录中找不到 mtg 可执行文件。"
    rm -rf "$tmpdir"
    exit 1
  fi

  mkdir -p /usr/local/bin
  mv "$dir/mtg" "$MTG_BIN"
  chmod +x "$MTG_BIN"

  cd / && rm -rf "$tmpdir"
  info "mtg 二进制已安装到 $MTG_BIN"
}

config_mtg() {
  if [ ! -x "$MTG_BIN" ]; then
    error "未找到 $MTG_BIN，请先执行安装。"
    exit 1
  fi

  mkdir -p /usr/local/etc

  echo
  read -rp "请输入 FakeTLS 伪装域名（默认 itunes.apple.com）: " domain
  [ -z "$domain" ] && domain="itunes.apple.com"

  read -rp "请输入本机监听端口（默认 8443，NAT 机请填内网监听端口）: " port
  [ -z "$port" ] && port="8443"

  info "生成 FakeTLS secret..."
  # mtg v2 推荐的 FakeTLS 生成方式，输出以 ee 开头
  local secret
  secret=$("$MTG_BIN" generate-secret --hex "$domain")
  if [ -z "$secret" ]; then
    error "生成 secret 失败，请检查 mtg 是否工作正常。"
    exit 1
  fi

  cat > "$MTG_CONF" <<EOF
# mtg 配置文件，至少需要 secret 和 bind-to 两项
# FakeTLS 域名: $domain
secret = "$secret"
bind-to = "0.0.0.0:$port"
EOF

  info "配置已写入 $MTG_CONF"
}

create_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "未检测到 systemd，不创建服务。你可以手动后台运行："
    echo "  $MTG_BIN run $MTG_CONF &"
    return 0
  fi

  cat > "$MTG_SERVICE" <<EOF
[Unit]
Description=Telegram MTProto proxy (mtg)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$MTG_BIN run $MTG_CONF
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable mtg >/dev/null 2>&1 || true
  systemctl restart mtg || {
    error "启动 mtg systemd 服务失败，请用 'journalctl -u mtg -e' 查看日志。"
    return 1
  }
  info "mtg 已作为 systemd 服务运行。"
}

show_info() {
  if [ ! -f "$MTG_CONF" ] || [ ! -x "$MTG_BIN" ]; then
    error "未检测到已安装的 mtg（$MTG_BIN / $MTG_CONF）。"
    exit 1
  fi

  local port secret
  port=$(grep -E '^bind-to' "$MTG_CONF" | sed -E 's/.*:([0-9]+)"/\1/')
  secret=$(grep -E '^secret' "$MTG_CONF" | sed -E 's/.*"(.+)"/\1/')

  local ip
  ip=$(curl -s ipv4.ip.sb || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

  echo
  echo "================ Telegram 连接参数 ================"
  echo "  Server (外网 IP)：$ip"
  echo "  Port             ：$port"
  echo "  Secret           ：$secret"
  echo
  echo "tg://proxy?server=${ip}&port=${port}&secret=${secret}"
  echo "https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
  echo "==================================================="
  echo
  warn "NAT 机特别注意："
  echo "  1. 商家面板里要把【外网端口】映射到本机 ${port}；"
  echo "  2. Telegram 客户端里填的是【外网 IP＋外网端口】，不是内网地址。"
}

uninstall_mtg() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop mtg 2>/dev/null || true
    systemctl disable mtg 2>/dev/null || true
  fi

  rm -f "$MTG_BIN" "$MTG_CONF" "$MTG_SERVICE"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
  fi
  info "已卸载 mtg 和相关配置/服务文件。"
}

restart_mtg() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart mtg 2>/dev/null || {
      error "systemd 重启失败，请检查日志。"
      exit 1
    }
    info "已通过 systemd 重启 mtg 服务。"
  else
    warn "系统没有 systemd，请手动重启，例如："
    echo "  killall mtg  # 结束旧进程"
    echo "  $MTG_BIN run $MTG_CONF &"
  fi
}

install_all() {
  check_root
  detect_os
  install_deps
  detect_arch
  download_mtg
  config_mtg
  create_systemd_service
  show_info
}

show_help() {
  cat <<EOF
用法：bash $(basename "$0") [命令]

命令：
  install    安装并配置 mtg（推荐）
  info       显示当前连接信息（tg:// 链接等）
  restart    重启 mtg 服务
  uninstall  卸载 mtg 及配置/服务
  help       显示本帮助

示例：
  bash $(basename "$0") install
  bash $(basename "$0") info
EOF
}

main() {
  case "$1" in
    install)
      install_all
      ;;
    info)
      show_info
      ;;
    restart)
      restart_mtg
      ;;
    uninstall)
      uninstall_mtg
      ;;
    help|"")
      show_help
      ;;
    *)
      error "未知命令：$1"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
