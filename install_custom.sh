#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# GitHub configuration
GITHUB_USER="MuMuMuCODE"
REPO_NAME="x-ui"

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!\n" && exit 1

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
elif cat /etc/proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}Unsupported system version, please contact the author!${plain}\n" && exit 1
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
    echo -e "${red}Architecture detection failed, using default: ${arch}${plain}"
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
        echo -e "${red}Please use CentOS 7 or higher!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${yellow}For security reasons, you need to modify the port and account password after installation/update${plain}"
    read -p "Continue?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Set your username:" config_account
        echo -e "${yellow}Username will be set to: ${config_account}${plain}"
        read -p "Set your password:" config_password
        echo -e "${yellow}Password will be set to: ${config_password}${plain}"
        read -p "Set panel access port:" config_port
        echo -e "${yellow}Panel port will be set to: ${config_port}${plain}"
        echo -e "${yellow}Configuring...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}Username and password configured${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}Panel port configured${plain}"
    else
        echo -e "${red}Cancelled, using default settings. Please modify them later.${plain}"
    fi
}

install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to detect x-ui version, may be Github API limit, please try again or specify version manually${plain}"
            exit 1
        fi
        echo -e "Detected latest version: ${last_version}, starting installation"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download failed, please ensure your server can download files from Github${plain}"
            exit 1
        fi
    else
        last_version=$1
        echo -e "Starting installation of x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui v$1 failed, please ensure this version exists${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    
    # Check for release-package directory (from GitHub Actions build)
    if [ -d "release-package" ]; then
        cd release-package
        mkdir -p bin
        # Move xray binary to bin directory
        if [ -f "xray-linux-${arch}" ]; then
            mv xray-linux-${arch} bin/xray
        fi
    else
        # Fallback to old directory structure
        if [ -d "x-ui" ]; then
            cd x-ui
        fi
    fi
    
    chmod +x x-ui bin/xray
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/main/x-ui.sh"
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} installation completed, panel started"
    echo -e ""
    echo -e "x-ui management script usage:"
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Show management menu"
    echo -e "x-ui start        - Start x-ui panel"
    echo -e "x-ui stop         - Stop x-ui panel"
    echo -e "x-ui restart      - Restart x-ui panel"
    echo -e "x-ui status       - Show x-ui status"
    echo -e "x-ui enable       - Enable x-ui at startup"
    echo -e "x-ui disable      - Disable x-ui at startup"
    echo -e "x-ui log          - Show x-ui logs"
    echo -e "x-ui v2-ui        - Migrate v2-ui data to x-ui"
    echo -e "x-ui update       - Update x-ui panel"
    echo -e "x-ui install      - Install x-ui panel"
    echo -e "x-ui uninstall    - Uninstall x-ui panel"
    echo -e "----------------------------------------------"
}

echo -e "${green}Starting installation${plain}"
install_base
install_x-ui $1
