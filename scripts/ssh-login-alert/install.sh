#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="ssh-login-alert"
SCRIPT_VERSION="1.0.0"

# ===== 颜色输出 =====
if [ -t 1 ]; then
  RED='\033[31m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  BLUE='\033[34m'
  CYAN='\033[36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  RESET=''
fi

info() {
  echo -e "${CYAN}ℹ️  $*${RESET}"
}

ok() {
  echo -e "${GREEN}✅ $*${RESET}"
}

warn() {
  echo -e "${YELLOW}⚠️  $*${RESET}"
}

err() {
  echo -e "${RED}❌ $*${RESET}"
}

title() {
  echo
  echo -e "${BOLD}${BLUE}===== $* =====${RESET}"
}

SCRIPT_PATH="/usr/local/bin/ssh-login-alert.sh"
ENV_FILE="/root/.tg-ssh-alert.env"
PAM_FILE="/etc/pam.d/sshd"
PAM_LINE="session optional pam_exec.so seteuid ${SCRIPT_PATH}"

if [ "$(id -u)" -ne 0 ]; then
  err "请使用 root 执行。"
  exit 1
fi

uninstall_common() {
  title "卸载 SSH 登录 Telegram 通知"

  if [ -f "$PAM_FILE" ]; then
    if grep -Fq "$SCRIPT_PATH" "$PAM_FILE"; then
      cp "$PAM_FILE" "${PAM_FILE}.bak.$(date +%Y%m%d%H%M%S)"
      sed -i "\#${SCRIPT_PATH}#d" "$PAM_FILE"
      ok "已从 PAM 中移除 SSH 登录通知接入。"
    else
      warn "PAM 中未发现 SSH 登录通知接入，跳过。"
    fi
  else
    warn "未找到 $PAM_FILE，跳过 PAM 清理。"
  fi

  if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH"
    ok "已删除登录通知脚本：$SCRIPT_PATH"
  else
    warn "未找到登录通知脚本，跳过。"
  fi
}

if [ "${1:-}" = "uninstall" ]; then
  uninstall_common

  if [ -f "$ENV_FILE" ]; then
    warn "Telegram 配置文件已保留：$ENV_FILE"
    info "如需彻底删除配置文件，可执行：bash /root/install-ssh-login-tg-alert.sh purge"
  fi

  title "卸载完成"
  exit 0
fi

if [ "${1:-}" = "purge" ]; then
  uninstall_common

  if [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
    ok "已删除 Telegram 配置文件：$ENV_FILE"
  else
    warn "未找到 Telegram 配置文件，跳过。"
  fi

  title "彻底卸载完成"
  exit 0
fi

title "SSH 登录 Telegram 通知安装脚本"

read -rp "请输入 Telegram Bot Token: " TG_BOT_TOKEN
read -rp "请输入 Telegram Chat ID: " TG_CHAT_ID
read -rp "请输入服务器公网 IP，可留空自动检测: " SERVER_PUBLIC_IP

if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
  err "Bot Token 或 Chat ID 不能为空。"
  exit 1
fi

if [ -n "$SERVER_PUBLIC_IP" ]; then
  if [[ "$SERVER_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ok "已设置手动公网 IP：$SERVER_PUBLIC_IP"
  else
    err "服务器公网 IP 格式不正确，请重新执行脚本。"
    exit 1
  fi
else
  warn "未填写服务器公网 IP，将使用自动检测。"
fi

title "安装 curl"

if command -v apt >/dev/null 2>&1; then
  apt update
  apt install -y curl
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y curl
elif command -v yum >/dev/null 2>&1; then
  yum install -y curl
else
  warn "未检测到 apt/dnf/yum，请手动确认 curl 已安装。"
fi

title "写入 Telegram 配置"

cat > "$ENV_FILE" <<ENV_EOF
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP}"
ENV_EOF

chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok "Telegram 配置已写入：$ENV_FILE"

title "写入 SSH 登录通知脚本"

cat > "$SCRIPT_PATH" <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/root/.tg-ssh-alert.env"

[ -f "$ENV_FILE" ] || exit 0

# 配置文件必须是 root 拥有，避免被普通用户篡改后通过 PAM 执行
OWNER="$(stat -c '%U:%G' "$ENV_FILE" 2>/dev/null || echo unknown)"
if [ "$OWNER" != "root:root" ]; then
  exit 0
fi

source "$ENV_FILE"

[ "${PAM_TYPE:-}" = "open_session" ] || exit 0

USER_NAME="${PAM_USER:-unknown}"
REMOTE_HOST="${PAM_RHOST:-unknown}"
TTY_NAME="${PAM_TTY:-unknown}"
SERVER_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

get_public_ip() {
  local ip=""
  local token=""

  # 1. AWS EC2 IMDSv2
  token="$(curl -fsS --connect-timeout 1 --max-time 2 \
    -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)"

  if [ -n "$token" ]; then
    ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
      -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "${ip}|AWS Metadata IMDSv2"
      return
    fi
  fi

  # 2. AWS EC2 IMDSv1 fallback
  ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
    "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|AWS Metadata IMDSv1"
    return
  fi

  # 3. GCP Metadata
  ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
    -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|GCP Metadata"
    return
  fi

  # 4. Azure Metadata
  ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
    -H "Metadata: true" \
    "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null || true)"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|Azure Metadata"
    return
  fi

  # 5. Oracle Cloud Metadata
  ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
    -H "Authorization: Bearer Oracle" \
    "http://169.254.169.254/opc/v2/vnics/" 2>/dev/null \
    | grep -m1 -oE "\"publicIp\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | sed -E "s/.*\"publicIp\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/" || true)"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|Oracle Metadata"
    return
  fi

  # 6. DigitalOcean Metadata
  ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
    "http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address" 2>/dev/null || true)"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|DigitalOcean Metadata"
    return
  fi

  # 7. 外部公网 IP 服务 fallback
  # 注意：如果服务器走了 WARP / Proton / WireGuard，这里可能得到 VPN 出口 IP
  for url in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com" \
    "https://checkip.amazonaws.com" \
    "https://ipinfo.io/ip"
  do
    ip="$(curl -4 -fsS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null | tr -d "[:space:]" || true)"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "${ip}|External API"
      return
    fi
  done

  # 8. 最后兜底：本机第一个 IP，通常是内网 IP
  ip="$(hostname -I 2>/dev/null | awk "{print \$1}")"

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}|hostname fallback"
    return
  fi

  echo "unknown|unknown"
}

if [ -n "${SERVER_PUBLIC_IP:-}" ]; then
  if [[ "$SERVER_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP="$SERVER_PUBLIC_IP"
    IP_SOURCE="Manual config"
  else
    IP_RESULT="$(get_public_ip)"
    SERVER_IP="${IP_RESULT%%|*}"
    IP_SOURCE="${IP_RESULT#*|}"
  fi
else
  IP_RESULT="$(get_public_ip)"
  SERVER_IP="${IP_RESULT%%|*}"
  IP_SOURCE="${IP_RESULT#*|}"
fi

LOGIN_TIME="$(date "+%Y-%m-%d %H:%M:%S %Z")"

MESSAGE=$(cat <<EOF
🔐 SSH 登录通知

主机: ${SERVER_HOSTNAME}
公网IP: ${SERVER_IP}
IP来源: ${IP_SOURCE}
用户: ${USER_NAME}
来源IP: ${REMOTE_HOST}
终端: ${TTY_NAME}
时间: ${LOGIN_TIME}
EOF
)

curl -fsS --connect-timeout 3 --max-time 5 \
  -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT_ID}" \
  --data-urlencode "text=${MESSAGE}" \
  >/dev/null 2>&1 || true

exit 0
SCRIPT_EOF

chown root:root "$SCRIPT_PATH"
chmod 700 "$SCRIPT_PATH"
ok "SSH 登录通知脚本已写入：$SCRIPT_PATH"

title "接入 PAM SSH 登录流程"

if [ ! -f "$PAM_FILE" ]; then
  err "未找到 $PAM_FILE，无法自动接入 PAM。"
  exit 1
fi

if grep -Fq "$SCRIPT_PATH" "$PAM_FILE"; then
  warn "PAM 中已存在 ssh-login-alert.sh，跳过重复添加。"
else
  cp "$PAM_FILE" "${PAM_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  echo "$PAM_LINE" >> "$PAM_FILE"
  ok "已添加 PAM 配置。"
fi

title "发送测试 Telegram 消息"

if [ -n "$SERVER_PUBLIC_IP" ]; then
  TEST_IP_SOURCE="Manual config"
else
  TEST_IP_SOURCE="Auto detect on login"
fi

TEST_MESSAGE="✅ SSH 登录通知脚本已安装

主机: $(hostname -f 2>/dev/null || hostname)
公网IP来源: ${TEST_IP_SOURCE}
时间: $(date "+%Y-%m-%d %H:%M:%S %Z")"

if curl -fsS --connect-timeout 3 --max-time 5 \
  -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT_ID}" \
  --data-urlencode "text=${TEST_MESSAGE}" \
  >/dev/null; then
  ok "测试消息发送成功。"
else
  warn "测试消息发送失败，请检查 Bot Token / Chat ID / 网络。"
fi

title "安装结果检查"

if [ -x "$SCRIPT_PATH" ]; then
  ok "登录通知脚本存在且可执行："
  ls -l "$SCRIPT_PATH"
else
  err "登录通知脚本不存在或不可执行：$SCRIPT_PATH"
fi

if grep -Fq "$SCRIPT_PATH" "$PAM_FILE"; then
  echo
  ok "PAM 已接入："
  grep -n "$SCRIPT_PATH" "$PAM_FILE"
else
  echo
  err "PAM 未检测到接入行：$SCRIPT_PATH"
fi

if [ -f "$ENV_FILE" ]; then
  echo
  ok "Telegram 配置文件存在："
  ls -l "$ENV_FILE"

  OWNER="$(stat -c '%U:%G:%a' "$ENV_FILE" 2>/dev/null || echo unknown)"
  info "Telegram 配置文件权限：$OWNER"

  if grep -q '^SERVER_PUBLIC_IP="[^"]' "$ENV_FILE"; then
    ok "已配置手动公网 IP 优先。"
  else
    warn "未配置手动公网 IP，将自动检测公网 IP。"
  fi
else
  echo
  err "Telegram 配置文件不存在：$ENV_FILE"
fi

title "安装完成"

ok "请新开一个 SSH 窗口登录测试。"
warn "当前窗口先不要断开。"

echo
info "手动检查命令："
echo "ls -l /usr/local/bin/ssh-login-alert.sh"
echo "grep -n ssh-login-alert.sh /etc/pam.d/sshd"
echo "ls -l /root/.tg-ssh-alert.env"

echo
info "卸载命令（保留tg-ssh-alert.env）："
echo "bash /root/install-ssh-login-tg-alert.sh uninstall"

echo
info "彻底卸载命令："
echo "bash /root/install-ssh-login-tg-alert.sh purge"
