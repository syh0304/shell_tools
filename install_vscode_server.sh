#!/bin/bash
#====================================================#
#   🚀 VS Code Server 全能脚本
#   默认：显示状态 | -i：安装 | 安全智能，不误操作
#====================================================#

set -euo pipefail

# ========== 配置 ==========
SERVICE_NAME="vscode-server"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CODE_BIN="/usr/local/bin/code-cli"
PORT=8080
ARCH=$(uname -m)
USER="${SUDO_USER:-$USER}"
HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

case $ARCH in
  x86_64)   ARCH=x64 ;;
  aarch64)  ARCH=arm64 ;;
  *)        echo "❌ 不支持的架构: $ARCH" >&2; exit 1 ;;
esac

DOWNLOAD_URL="https://update.code.visualstudio.com/latest/cli-linux-${ARCH}/stable"
# ===================================================

# ========== 函数：显示状态 ==========
show_status() {
    echo "🔍 正在检查 VS Code Server 状态..."

    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo "🔴 未安装：未找到服务文件 $SERVICE_FILE"
        echo "💡 安装命令：$0 --install"
        exit 1
    fi

    if ! systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        echo "🟡 已安装但未启用"
        echo "🔧 启用服务：sudo systemctl enable --now $SERVICE_NAME"
        exit 1
    fi

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "🟡 服务已安装但未运行"
        echo "🚀 启动服务：sudo systemctl start $SERVICE_NAME"
        # 尝试提取地址（可能上次运行过）
        URL=$(sudo journalctl -u "$SERVICE_NAME" --no-pager | grep -o "http://[^ ]*tkn=[^ ]*" | tail -n1)
        if [[ -n "$URL" ]]; then
            IP=$(echo "$URL" | sed "s|0.0.0.0|$(hostname -I | awk '{print $1}' || echo 'your-server-ip')|")
            echo "📌 上次访问地址（服务未运行）：$IP"
        fi
        exit 1
    fi

    URL=$(sudo journalctl -u "$SERVICE_NAME" --no-pager | grep -o "http://[^ ]*tkn=[^ ]*" | tail -n1)
    if [[ -z "$URL" ]]; then
        # 日志没有 URL，则尝试从服务文件解析 token
        if [[ -f "$SERVICE_FILE" ]]; then
            TOKEN_FROM_SVC=$(grep -oE "--connection-token\s+[^ ]+" "$SERVICE_FILE" | awk '{print $2}' || true)
            if [[ -n "${TOKEN_FROM_SVC:-}" ]]; then
                IP_ADDR=$(hostname -I | awk '{print $1}' || echo 'your-server-ip')
                URL="http://${IP_ADDR}:${PORT}?tkn=${TOKEN_FROM_SVC}"
            fi
        fi
        if [[ -z "$URL" ]]; then
            echo "⚠️  服务运行中，但未找到访问地址"
            echo "🔍 查看日志：sudo journalctl -u $SERVICE_NAME -f"
            exit 1
        fi
    fi

    IP=$(echo "$URL" | sed "s|0.0.0.0|$(hostname -I | awk '{print $1}' || echo 'your-server-ip')|")

    echo "=================================================="
    echo "🟢 VS Code Server 正在运行！"
    echo "🌐 访问地址: $IP"
    echo "🔐 Token 已包含在链接中，请勿泄露"
    echo "📌 提示：复制整个链接到浏览器打开"
    echo "⏹️  停止服务: sudo systemctl stop $SERVICE_NAME"
    echo "🔄 重启服务: sudo systemctl restart $SERVICE_NAME"
    echo "=================================================="
}

# ========== 函数：安装 ==========
# ========== 函数：安装 ==========

# ========== 函数：安装 ==========
install_server() {
    echo "🚀 开始安装 VS Code Server..."

    # 1. 清理旧状态
    echo "🧹 清理旧服务..."
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "$CODE_BIN"
    sudo rm -f "$SERVICE_FILE"

    # 2. 下载 CLI
    TMP_TAR="/tmp/code-cli.tar.gz"
    TMP_DIR="/tmp/vscode-install-$RANDOM"
    mkdir -p "$TMP_DIR"

    echo "📥 正在下载 CLI..."
    for i in {1..3}; do
        if curl -# -f -L -o "$TMP_TAR" "$DOWNLOAD_URL"; then
            echo "✔ 下载成功"
            break
        else
            echo "🔁 第 $i 次下载失败，2 秒后重试..."
            sleep 2
        fi
    done

    if [[ ! -f "$TMP_TAR" ]]; then
        echo "❌ 下载失败，请检查网络"
        exit 1
    fi

    tar -xzf "$TMP_TAR" -C "$TMP_DIR"
    rm -f "$TMP_TAR"

    if [[ ! -f "$TMP_DIR/code" ]]; then
        echo "❌ 解压失败：未找到 'code' 文件"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    sudo mv "$TMP_DIR/code" "$CODE_BIN"
    sudo chmod +x "$CODE_BIN"
    rm -rf "$TMP_DIR"

    echo "✅ CLI 已安装到: $CODE_BIN"

    # 3. 设置用户名和密码
    echo "🔐 设置用户名和密码访问..."
    read -p "请输入用户名: " USERNAME
    while true; do
        read -sp "请输入密码: " PASSWORD
        echo
        read -sp "请再次输入密码: " PASSWORD_CONFIRM
        echo
        if [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]]; then
            break
        else
            echo "❌ 密码不匹配，请重新输入"
        fi
    done

    # 创建密码文件目录
    PASSWORD_DIR="/etc/vscode-server"
    PASSWORD_FILE="$PASSWORD_DIR/passwd"
    sudo mkdir -p "$PASSWORD_DIR"
    echo "$USERNAME:$PASSWORD" | sudo tee "$PASSWORD_FILE" > /dev/null
    sudo chmod 600 "$PASSWORD_FILE"
    echo "✅ 用户凭证已保存到: $PASSWORD_FILE"

    # 4. 创建服务文件
    echo "📝 创建 systemd 服务..."
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=VS Code Server
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$CODE_BIN serve-web --host 0.0.0.0 --port $PORT --without-connection-token --accept-server-license-terms --verbose --server-data-dir $HOME_DIR/.vscode-server
Environment=SHELL=/bin/bash
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # 5. 防火墙
    echo "🛡️  防火墙放行 $PORT/tcp"
    if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
        sudo firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null 2>&1 || true
        sudo firewall-cmd --reload >/dev/null 2>&1 || true
    fi

    # 6. 启动服务
    echo "🔄 启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"

    sleep 3
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "❌ 服务启动失败！运行查看日志："
        echo "   sudo journalctl -u $SERVICE_NAME -f"
        exit 1
    fi

    IP=$(hostname -I | awk '{print $1}' || echo "your-server-ip")
    echo "=================================================="
    echo "🎉 安装成功！"
    echo "🌐 访问地址: http://$IP:$PORT"
    echo "👤 用户名: $USERNAME"
    echo "🔑 密码: ****** (您刚才设置的密码)"
    echo "📌 已设置开机自启"
    echo "💡 提示：访问时浏览器会弹出用户名/密码输入框"
    echo "=================================================="
}

# ========== 函数：卸载 ==========
# ========== 函数：卸载 ==========
uninstall_server() {
    echo "🛑 正在卸载 VS Code Server..."

    # 1. 停止并禁用服务
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "⏹️ 停止服务..."
        sudo systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo "🚫 禁用服务..."
        sudo systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi

    # 2. 删除服务文件
    echo "🗑️ 删除服务文件..."
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload

    # 3. 删除 CLI 二进制
    echo "🗑️ 删除 CLI 二进制..."
    sudo rm -f "$CODE_BIN"

    # 4. 删除用户数据（可选）
    echo "🗑️ 删除 VS Code 用户数据（缓存、扩展等）..."
    # 使用 -rf 递归删除目录及其内容，而不是仅仅尝试删除目录本身
    rm -rf "$HOME_DIR/.vscode-server" 2>/dev/null || true
    rm -rf "$HOME_DIR/.vscode" 2>/dev/null || true

    # 5. 删除密码文件
    echo "🗑️ 删除密码文件..."
    sudo rm -f "/etc/vscode-server/passwd"
    sudo rmdir "/etc/vscode-server" 2>/dev/null || true  # 只有当目录为空时才删除

    # 6. 防火墙规则清理（尽力而为）
    echo "🛡️ 清理防火墙规则（端口 $PORT/tcp）..."
    if command -v ufw &>/dev/null && sudo ufw status | grep -q "$PORT/tcp"; then
        sudo ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
        sudo firewall-cmd --permanent --remove-port="$PORT/tcp" >/dev/null 2>&1 || true
        sudo firewall-cmd --reload >/dev/null 2>&1 || true
    fi

    echo "=================================================="
    echo "✅ 卸载完成！"
    echo "📌 所有相关文件和服务已删除"
    echo "🚀 如需重新安装：$0 --install"
    echo "=================================================="
}

# ========== 主逻辑 ==========
case "${1:-}" in
    -i|--install|install)
        install_server
        ;;
    -u|--uninstall|uninstall)
        uninstall_server
        ;;
    -h|--help|help)
    echo "Usage: $0 [option]"
    echo "  (no args)     显示 VS Code Server 状态和访问地址"
    echo "  -i, --install  安装或重装 VS Code Server"
    echo "  -u, --uninstall 卸载 VS Code Server（彻底清理）"
    echo "  -h, --help     显示帮助"
    exit 0
        ;;
    "")
        show_status
        ;;
    *)
        echo "❌ 未知参数: $1"
        echo "💡 使用 -h 查看帮助"
        exit 1
        ;;
esac