#!/bin/bash

# 中文说明：
# 这是一个用于在 Debian 12 上一键安装 OBS Studio 的 Shell 脚本
# 功能包括：更新系统、添加 OBS 官方仓库、安装 OBS Studio

echo "正在更新系统软件包..."
sudo apt update && sudo apt upgrade -y

echo "安装必要的依赖工具..."
sudo apt install -y wget apt-transport-https gnupg ca-certificates

echo "下载并添加 OBS Studio 的 GPG 公钥..."
wget -qO - https://obsproject.com/download/obs-studio-debian.pubkey | sudo gpg --dearmor -o /usr/share/keyrings/obs-studio-archive-keyring.gpg

echo "添加 OBS Studio 官方 APT 仓库..."
echo "deb [signed-by=/usr/share/keyrings/obs-studio-archive-keyring.gpg] https://download.opensuse.org/repositories/video:/media:/obs:/release/Debian_12/ ./" | sudo tee /etc/apt/sources.list.d/obs-studio.list

echo "更新软件包列表（包含新添加的 OBS 仓库）..."
sudo apt update

echo "安装 OBS Studio..."
sudo apt install -y obs-studio

echo "OBS Studio 安装完成！"
echo "您可以在应用程序菜单中启动 OBS Studio，或在终端输入 'obs' 来运行。"