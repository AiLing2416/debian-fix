#!/bin/bash
# Debian 系统体验修复脚本（支持 IPv6 only / 小内存 VPS 语言环境修复）
# 适用于无图形化 Debian

set -e

echo "=== 检查 root 权限 ==="
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行本脚本"
    exit 1
fi

echo "=== 检测 Debian 版本 ==="
VERSION_CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
if [ -z "$VERSION_CODENAME" ]; then
    echo "无法检测 Debian 版本代号，退出"
    exit 1
fi
echo "检测到版本：$VERSION_CODENAME"

echo "=== 检测 IP 类型 ==="
HAS_IPV4=false
HAS_IPV6=false

if ip -4 addr show | grep -q "inet "; then
    HAS_IPV4=true
fi
if ip -6 addr show | grep "inet6 " | grep -vq "fe80"; then
    HAS_IPV6=true
fi

echo "=== 设置 DNS ==="

# 解锁 resolv.conf（如果已锁）
if lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i'; then
    chattr -i /etc/resolv.conf
fi

rm -f /etc/resolv.conf
touch /etc/resolv.conf

if $HAS_IPV4 && $HAS_IPV6; then
    echo "检测到 双栈 IPv4+IPv6"
    cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF
elif $HAS_IPV4; then
    echo "检测到 仅 IPv4"
    cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
elif $HAS_IPV6; then
    echo "检测到 仅 IPv6"
    cat >/etc/resolv.conf <<EOF
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF
else
    echo "未检测到 IP 地址，使用默认 IPv4 DNS"
    cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# 改完再锁定
chattr +i /etc/resolv.conf

echo "=== 恢复官方软件源 ==="
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $VERSION_CODENAME-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $VERSION_CODENAME-security main contrib non-free non-free-firmware
EOF

echo "=== 更新 apt 并启用并行下载 ==="
apt update
mkdir -p /etc/apt/apt.conf.d
echo 'Acquire::Queue-Mode "host";' > /etc/apt/apt.conf.d/99parallel
echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99parallel

echo "=== 安装常用工具 ==="
apt install -y bash-completion curl wget vim htop dnsutils ca-certificates apt-transport-https lsb-release iproute2

echo "=== 启用 bash 补全 ==="
if ! grep -q "bash_completion" ~/.bashrc; then
    echo "[ -f /etc/bash_completion ] && . /etc/bash_completion" >> ~/.bashrc
fi

echo "=== 修复语言环境为 en_US.UTF-8 ==="
apt install -y locales

# 只保留 en_US.UTF-8
sed -i '/^[^#]/s/^/#/' /etc/locale.gen
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

# 临时加 swap 防止 OOM
fallocate -l 512M /tmp/locale_swap
chmod 600 /tmp/locale_swap
mkswap /tmp/locale_swap
swapon /tmp/locale_swap

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8

swapoff /tmp/locale_swap
rm /tmp/locale_swap

echo "=== 启用命令历史时间戳 ==="
if ! grep -q "HISTTIMEFORMAT" ~/.bashrc; then
    echo 'export HISTTIMEFORMAT="%F %T "' >> ~/.bashrc
fi

echo "=== 清理 apt 缓存 ==="
apt clean

echo "=== 当前系统语言 ==="
locale | grep LANG

echo "=== 当前 DNS 配置 ==="
cat /etc/resolv.conf

echo "=== 修复完成，请重新登录以生效 ==="
