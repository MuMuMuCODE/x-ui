#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 获取版本号，默认为当前时间戳
VERSION=${1:-$(date +%Y%m%d%H%M%S)}

echo -e "${green}开始构建 x-ui 安装包，版本: ${VERSION}${plain}"

# 检测架构
arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${yellow}检测到架构: ${arch}${plain}"
fi

echo -e "目标架构: ${arch}"

# 清理旧的构建文件
echo -e "${yellow}清理旧的构建文件...${plain}"
rm -rf x-ui-package
rm -f x-ui-linux-${arch}-${VERSION}.tar.gz

# 创建工作目录
mkdir -p x-ui-package

# 编译 x-ui 主程序
echo -e "${green}编译 x-ui 主程序...${plain}"
cd /mnt/d/节点面板/x-ui
CGO_ENABLED=1 GOOS=linux GOARCH=${arch} go build -o x-ui-package/x-ui main.go
if [[ $? -ne 0 ]]; then
    echo -e "${red}编译 x-ui 失败${plain}"
    exit 1
fi

# 复制 x-ray 二进制文件
echo -e "${green}复制 x-ray 二进制文件...${plain}"
cp bin/xray-linux-${arch} x-ui-package/bin/xray
if [[ ! -f x-ui-package/bin/xray ]]; then
    echo -e "${red}未找到 x-ray 二进制文件，请先准备 bin/xray-linux-${arch}${plain}"
    exit 1
fi

# 复制 web 目录
echo -e "${green}复制 web 资源...${plain}"
cp -r web x-ui-package/

# 复制配置文件
echo -e "${green}复制配置文件...${plain}"
cp config/ x-ui-package/ -r

# 复制数据库文件
echo -e "${green}复制数据库文件...${plain}"
cp database/ x-ui-package/ -r

# 复制工具目录
echo -e "${green}复制工具目录...${plain}"
cp -r util x-ui-package/

# 复制日志目录
echo -e "${green}复制日志目录...${plain}"
cp -r logger x-ui-package/

# 复制 v2ui 目录
echo -e "${green}复制 v2ui 目录...${plain}"
cp -r v2ui x-ui-package/

# 复制 xray 目录
echo -e "${green}复制 xray 目录...${plain}"
cp -r xray x-ui-package/

# 复制 systemd 服务文件
echo -e "${green}复制服务文件...${plain}"
cp x-ui.service x-ui-package/

# 复制管理脚本
echo -e "${green}复制管理脚本...${plain}"
cp x-ui.sh x-ui-package/

# 复制 LICENSE
cp LICENSE x-ui-package/

# 复制 README
cp README.md x-ui-package/

# 打包
echo -e "${green}打包安装包...${plain}"
cd x-ui-package
tar -czvf ../x-ui-linux-${arch}-${VERSION}.tar.gz *

# 清理工作目录
cd ..
rm -rf x-ui-package

echo -e "${green}构建完成！${plain}"
echo -e "安装包位置: x-ui-linux-${arch}-${VERSION}.tar.gz"
echo -e ""
echo -e "下一步操作："
echo -e "1. 上传 x-ui-linux-${arch}-${VERSION}.tar.gz 到 GitHub Releases"
echo -e "2. 修改 install_custom.sh 中的 GITHUB_USER 和 REPO_NAME"
echo -e "3. 分享安装命令: bash <(curl -Ls 你的raw文件链接)"
