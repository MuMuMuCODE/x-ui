#!/bin/bash

#======================================
# x-ui 自定义安装脚本
# 支持从 GitHub Releases 下载预编译安装包
#======================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#======================================
# 配置部分 - 请根据实际情况修改
#======================================
GITHUB_USER="MuMuMuCODE"
REPO_NAME="x-ui"
#======================================

print_msg() {
    echo -e "${GREEN}[x-ui]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[Warning]${NC} $1"
}

print_error() {
    echo -e "${RED}[Error]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户运行此脚本"
        print_warn "尝试使用 sudo 运行..."
        return 1
    fi
    return 0
}

# 检查操作系统
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS="unknown"
    fi
    
    case $OS in
        ubuntu|debian)
            print_msg "检测到系统: $OS"
            ;;
        centos|rhel|fedora)
            print_msg "检测到系统: $OS"
            ;;
        alpine)
            print_msg "检测到系统: $OS"
            ;;
        *)
            print_warn "未完全支持的操作系统: $OS，继续安装..."
            ;;
    esac
}

# 检查架构
check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l|armhf)
            print_error "不支持 armv7/armhf 架构"
            exit 1
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    print_msg "系统架构: $ARCH"
}

# 检查系统位数
check_bits() {
    if [ "$(getconf LONG_BIT)" -eq 64 ]; then
        BITS="64"
    else
        BITS="32"
    fi
}

# 获取版本号
get_version() {
    if [ -n "$1" ]; then
        CUSTOM_VERSION="$1"
    else
        # 获取最新版本
        CUSTOM_VERSION=$(curl -s "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/releases/latest" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
        if [ -z "$CUSTOM_VERSION" ]; then
            print_error "无法获取最新版本号"
            exit 1
        fi
    fi
    print_msg "安装版本: $CUSTOM_VERSION"
}

# 检查版本兼容性
check_version_compatibility() {
    print_msg "检查版本兼容性..."
    
    # 某些版本可能有特定要求
    local min_version="v1.0.0"
    
    if [ "$(printf '%s\n' "$min_version" "$CUSTOM_VERSION" | sort -V | head -n1)" != "$min_version" ]; then
        print_warn "版本 $CUSTOM_VERSION 较旧，可能存在已知问题"
    fi
}

# 安装基础依赖
install_dependencies() {
    print_msg "安装基础依赖..."
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y curl wget unzip tar
    elif command -v yum &> /dev/null; then
        yum install -y curl wget unzip tar
    elif command -v apk &> /dev/null; then
        apk add --no-cache curl wget unzip tar
    fi
}

# 停止现有服务
stop_service() {
    print_msg "停止现有服务..."
    
    # 尝试停止服务
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        systemctl stop x-ui
        print_msg "已停止 x-ui 服务"
    fi
    
    if pgrep -x "x-ui" > /dev/null 2>&1; then
        pkill x-ui
        print_msg "已终止 x-ui 进程"
    fi
}

# 备份现有配置
backup_existing() {
    if [ -f "/usr/local/x-ui/x-ui" ]; then
        print_warn "检测到已安装的 x-ui，正在备份..."
        BACKUP_DIR="/tmp/x-ui-backup-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r /usr/local/x-ui/* "$BACKUP_DIR/" 2>/dev/null || true
        print_msg "备份保存至: $BACKUP_DIR"
    fi
}

# 下载并解压安装包
download_and_extract() {
    print_msg "从 GitHub 下载安装包..."
    
    local download_url="https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${CUSTOM_VERSION}/x-ui-linux-${ARCH}-${CUSTOM_VERSION}.tar.gz"
    print_msg "下载链接: $download_url"
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 下载文件
    if ! curl -L -o x-ui.tar.gz "$download_url"; then
        print_error "下载失败，请检查版本号是否正确"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 解压
    print_msg "解压安装包..."
    tar -xzf x-ui.tar.gz
    
    # 安装
    print_msg "安装文件..."
    mkdir -p /usr/local/x-ui
    
    # 复制所有文件
    cp -r release-package/* /usr/local/x-ui/
    
    # 设置权限
    chmod +x /usr/local/x-ui/x-ui
    chmod +x /usr/local/x-ui/x-ui.sh
    
    # 清理
    cd /
    rm -rf "$temp_dir"
    
    print_msg "安装完成！"
}

# 配置 systemd 服务
configure_systemd() {
    print_msg "配置系统服务..."
    
    # 检查是否需要创建服务文件
    if [ ! -f "/etc/systemd/system/x-ui.service" ]; then
        cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=x-ui Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/x-ui
ExecStart=/usr/local/x-ui/x-ui
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        print_msg "服务文件已创建"
    fi
}

# 安装后配置
post_install() {
    print_msg "完成安装后配置..."
    
    # 提示用户进行基础配置
    print_msg ""
    print_msg "======================================"
    print_msg "  x-ui 安装完成！"
    print_msg "======================================"
    print_msg ""
    print_warn "请进行以下初始配置："
    print_msg ""
    print_msg "1. 设置管理员账户和密码："
    print_msg "   /usr/local/x-ui/x-ui setting -username admin -password your_password"
    print_msg ""
    print_msg "2. 设置面板访问端口："
    print_msg "   /usr/local/x-ui/x-ui setting -port 2053"
    print_msg ""
    print_msg "3. 启动服务："
    print_msg "   systemctl start x-ui"
    print_msg "   systemctl enable x-ui"
    print_msg ""
    print_msg "4. 查看服务状态："
    print_msg "   systemctl status x-ui"
    print_msg ""
    print_msg "5. 查看面板："
    print_msg "   http://你的服务器IP:2053"
    print_msg ""
}

# 管理命令说明
show_commands() {
    print_msg ""
    print_msg "======================================"
    print_msg "  管理命令"
    print_msg "======================================"
    print_msg ""
    print_msg "启动服务: systemctl start x-ui"
    print_msg "停止服务: systemctl stop x-ui"
    print_msg "重启服务: systemctl restart x-ui"
    print_msg "查看状态: systemctl status x-ui"
    print_msg "开机自启: systemctl enable x-ui"
    print_msg "禁用自启: systemctl disable x-ui"
    print_msg ""
    print_msg "查看日志: journalctl -u x-ui -f"
    print_msg "配置文件: /usr/local/x-ui/config.json"
    print_msg ""
}

# 主函数
main() {
    print_msg "======================================"
    print_msg "  x-ui 自定义安装脚本"
    print_msg "======================================"
    print_msg ""
    
    # 检查参数
    if [ -n "$1" ]; then
        CUSTOM_VERSION="$1"
        print_msg "指定版本: $CUSTOM_VERSION"
    fi
    
    # 检查 root
    if ! check_root; then
        print_warn "请使用 sudo 重新运行此脚本"
        exit 1
    fi
    
    # 执行安装步骤
    check_os
    check_arch
    check_bits
    get_version "$CUSTOM_VERSION"
    check_version_compatibility
    install_dependencies
    stop_service
    backup_existing
    download_and_extract
    configure_systemd
    post_install
    show_commands
    
    print_msg ""
    print_msg "安装成功完成！"
}

# 运行主函数
main "$@"
