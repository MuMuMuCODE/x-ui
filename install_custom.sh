#!/bin/bash

#======================================
# x-ui Custom Installation Script
# Download pre-compiled packages from GitHub Releases
#======================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cur_dir=$(pwd)

#======================================
# Configuration - Please modify according to your setup
#======================================
GITHUB_USER="MuMuMuCODE"
REPO_NAME="x-ui"
#======================================

# check root
[[ $EUID -ne 0 ]] && echo -e "${RED}Error: ${plain} Must run as root user!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${RED}Failed to detect OS version, please contact the script author!\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${RED}Failed to detect architecture, using default: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "This software does not support 32-bit systems (x86), please use 64-bit systems (x86_64)"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${RED}Please use CentOS 7 or higher!\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${RED}Please use Ubuntu 16 or higher!\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${RED}Please use Debian 8 or higher!\n" && exit 1
    fi
fi

# Get version number
get_version() {
    if [ -n "$1" ]; then
        CUSTOM_VERSION="$1"
    else
        # Get latest version
        CUSTOM_VERSION=$(curl -s "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/releases/latest" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
        if [[ ! -n "$CUSTOM_VERSION" ]]; then
            echo -e "${RED}Failed to detect version, may have exceeded Github API limit, please try again later or manually specify version${plain}"
            exit 1
        fi
    fi
    echo -e "Installing x-ui version: ${CUSTOM_VERSION}"
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

# Stop existing service
stop_service() {
    echo "Stopping existing service..."
    systemctl stop x-ui 2>/dev/null || true
    pkill x-ui 2>/dev/null || true
}

# Backup existing installation
backup_existing() {
    if [ -f "/usr/local/x-ui/x-ui" ]; then
        echo -e "${YELLOW}Detected existing x-ui installation, backing up...${plain}"
        BACKUP_DIR="/tmp/x-ui-backup-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r /usr/local/x-ui/* "$BACKUP_DIR/" 2>/dev/null || true
        echo -e "Backup saved to: ${BACKUP_DIR}"
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${YELLOW}For security reasons, after installation/update you need to modify port, username and password${plain}"
    read -p "Continue with configuration?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Please set username:" config_account
        echo -e "${YELLOW}Username will be set to: ${config_account}${plain}"
        read -p "Please set password:" config_password
        echo -e "${YELLOW}Password will be set to: ${config_password}${plain}"
        read -p "Please set panel port:" config_port
        echo -e "${YELLOW}Port will be set to: ${config_port}${plain}"
        echo -e "${YELLOW}Applying configuration...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${YELLOW}Username and password configured${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${YELLOW}Port configured${plain}"
    else
        echo -e "${RED}Configuration skipped, all settings are default. Please modify them later${plain}"
    fi
}

# Download and install x-ui
install_x-ui() {
    get_version "$1"
    stop_service
    backup_existing
    install_base
    
    cd /usr/local/
    
    local download_url="https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${CUSTOM_VERSION}/x-ui-linux-${arch}-${CUSTOM_VERSION}.tar.gz"
    echo -e "Download URL: ${download_url}"
    
    wget -N --no-check-certificate -O x-ui.tar.gz ${download_url}
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Download failed, please check version number or network connection${plain}"
        exit 1
    fi
    
    # 解压
    mkdir -p x-ui-extract
    tar zxvf x-ui.tar.gz -C x-ui-extract
    rm x-ui.tar.gz -f
    
    # 检查是否有 release-package 目录
    if [ -d "x-ui-extract/release-package" ]; then
        cd x-ui-extract/release-package
    else
        cd x-ui-extract
    fi
    
    chmod +x x-ui bin/xray
    
    # 复制所有文件到安装目录
    mkdir -p /usr/local/x-ui
    cp -r * /usr/local/x-ui/
    
    cd /usr/local/
    rm -rf x-ui-extract
    
    # 设置权限
    chmod +x /usr/local/x-ui/x-ui
    chmod +x /usr/local/x-ui/bin/xray
    chmod +x /usr/local/x-ui/x-ui.sh
    
    # 配置服务
    cp -f /usr/local/x-ui/x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/main/x-ui.sh
    chmod +x /usr/bin/x-ui
    
    config_after_install
    
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${GREEN}x-ui v${CUSTOM_VERSION}${plain} installation completed, panel is running"
    echo -e ""
    echo -e "x-ui management script usage: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Show management menu"
    echo -e "x-ui start        - Start x-ui panel"
    echo -e "x-ui stop         - Stop x-ui panel"
    echo -e "x-ui restart      - Restart x-ui panel"
    echo -e "x-ui status       - Check x-ui status"
    echo -e "x-ui enable       - Enable x-ui on boot"
    echo -e "x-ui disable      - Disable x-ui on boot"
    echo -e "x-ui log          - View x-ui logs"
    echo -e "x-ui update       - Update x-ui panel"
    echo -e "x-ui install      - Install x-ui panel"
    echo -e "x-ui uninstall    - Uninstall x-ui panel"
    echo -e "----------------------------------------------"
}

echo -e "${GREEN}Starting installation${plain}"
install_x-ui $1



