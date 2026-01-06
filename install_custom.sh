#!/bin/bash

#=================================================================
# 自定义 x-ui 一键安装脚本
# 支持从 GitHub Releases 下载自定义编译版本
#=================================================================

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# 配置信息 - 请根据实际情况修改
GITHUB_USER="你的GitHub用户名"
REPO_NAME="x-ui"
BRANCH="main"

# 从命令行参数获取版本号，如果不指定则获取最新版本
CUSTOM_VERSION=$1

echo -e "${blue}========================================${plain}"
echo -e "${blue}  自定义 x-ui 一键安装脚本${plain}"
echo -e "${blue}========================================${plain}"
echo -e ""

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：必须使用root用户运行此脚本！${plain}\n" && exit 1

# 检查操作系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

echo -e "检测到系统: ${green}${release}${plain}"

# 检测架构
arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo -e "系统架构: ${green}${arch}${plain}"

# 检查系统位数
if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)"
    exit -1
fi

# 获取系统版本
os_version=""
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/os-release)
fi

# 版本兼容性检查
if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 安装基础依赖
install_base() {
    echo -e "${yellow}安装基础依赖...${plain}"
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

# 安装后配置
config_after_install() {
    echo -e ""
    echo -e "${yellow}========================================${plain}"
    echo -e "${yellow}  安全配置${plain}"
    echo -e "${yellow}========================================${plain}"
    echo -e "${yellow}出于安全考虑，安装完成后需要设置端口与账户密码${plain}"
    echo -e ""
    
    read -p "确认是否继续配置?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        echo -e ""
        read -p "请设置您的账户名:" config_account
        echo -e "${green}您的账户名将设定为: ${config_account}${plain}"
        
        read -p "请设置您的账户密码:" config_password
        echo -e "${green}您的账户密码将设定为: ${config_password}${plain}"
        
        read -p "请设置面板访问端口:" config_port
        echo -e "${green}您的面板访问端口将设定为: ${config_port}${plain}"
        
        echo -e ""
        echo -e "${yellow}开始应用配置...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${green}✓ 账户密码设置完成${plain}"
        
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${green}✓ 面板端口设置完成${plain}"
        
        echo -e ""
        echo -e "${green}========================================${plain}"
        echo -e "${green}  配置完成！${plain}"
        echo -e "${green}========================================${plain}"
    else
        echo -e "${yellow}已跳过配置，使用默认设置${plain}"
        echo -e "${yellow}请及时修改默认账户密码和端口！${plain}"
    fi
}

# 停止现有服务
stop_existing_service() {
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "${yellow}停止现有 x-ui 服务...${plain}"
        systemctl stop x-ui
    fi
}

# 下载并安装
install_x-ui() {
    echo -e ""
    echo -e "${green}========================================${plain}"
    echo -e "${green}  开始安装${plain}"
    echo -e "${green}========================================${plain}"
    
    # 停止现有服务
    stop_existing_service
    
    cd /usr/local/
    
    # 构造下载链接
    if [[ -n "$CUSTOM_VERSION" ]]; then
        last_version=$CUSTOM_VERSION
        download_url="https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "安装版本: ${green}${last_version}${plain}"
    else
        # 获取最新版本
        echo -e "正在获取最新版本..."
        last_version=$(curl -Ls "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取版本失败，请检查 GitHub 配置是否正确${plain}"
            echo -e "当前配置: ${GITHUB_USER}/${REPO_NAME}"
            exit 1
        fi
        download_url="https://github.com/${GITHUB_USER}/${REPO_NAME}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "最新版本: ${green}${last_version}${plain}"
    fi
    
    echo -e "下载地址: ${blue}${download_url}${plain}"
    echo -e ""
    echo -e "${yellow}下载安装包...${plain}"
    
    # 下载安装包
    wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "${download_url}"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败，请检查：${plain}"
        echo -e "1. 版本号是否正确"
        echo -e "2. GitHub 仓库是否存在"
        echo -e "3. 服务器能否访问 GitHub"
        exit 1
    fi
    
    echo -e "${green}下载完成${plain}"
    
    # 清理旧版本
    if [[ -e /usr/local/x-ui/ ]]; then
        echo -e "${yellow}清理旧版本...${plain}"
        rm -rf /usr/local/x-ui/
    fi
    
    # 解压安装包
    echo -e "${yellow}解压安装包...${plain}"
    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    
    # 进入目录并设置权限
    cd x-ui
    chmod +x x-ui bin/xray
    
    # 复制服务文件
    echo -e "${yellow}配置系统服务...${plain}"
    cp -f x-ui.service /etc/systemd/system/
    
    # 下载管理脚本
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/x-ui.sh"
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    
    # 运行安装后配置
    config_after_install
    
    # 启动服务
    echo -e ""
    echo -e "${yellow}启动服务...${plain}"
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    
    # 显示安装结果
    echo -e ""
    echo -e "${green}========================================${plain}"
    echo -e "${green}  安装完成！${plain}"
    echo -e "${green}========================================${plain}"
    echo -e ""
    echo -e "${green}面板已启动，请访问：${plain}"
    echo -e "${green}http://你的服务器IP:54321${plain}"
    echo -e ""
    echo -e "${yellow}管理命令：${plain}"
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单"
    echo -e "x-ui start        - 启动面板"
    echo -e "x-ui stop         - 停止面板"
    echo -e "x-ui restart      - 重启面板"
    echo -e "x-ui status       - 查看状态"
    echo -e "x-ui log          - 查看日志"
    echo -e "x-ui uninstall    - 卸载面板"
    echo -e "----------------------------------------------"
}

# 主程序
install_base
install_x-ui

echo -e ""
echo -e "${blue}感谢使用自定义 x-ui 安装脚本！${plain}"

