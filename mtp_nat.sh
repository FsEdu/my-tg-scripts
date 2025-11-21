#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: Alpine/CentOS/Debian/Ubuntu
#	Description: MTProxy Golang (Universal & NAT Optimized)
#	Version: 2.1.0-Universal
#	Modified by: Gemini AI
#=================================================

sh_ver="2.1.0-Universal"
filepath=$(cd "$(dirname "$0")"; pwd)
file="/usr/local/mtproxy-go"
mtproxy_file="${file}/mtg"
mtproxy_conf="${file}/mtproxy.conf"
mtproxy_run="${file}/mtp_run.sh"
mtproxy_log="${file}/mtproxy.log"

# 颜色定义
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

# 检查 Root 权限
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 请使用 Root 账号运行此脚本！" && exit 1
}

# 系统检测 (增强版)
check_sys(){
	if [[ -f /etc/alpine-release ]]; then
		release="alpine"
        install_cmd="apk add --no-cache"
	elif [[ -f /etc/redhat-release ]]; then
		release="centos"
        install_cmd="yum install -y"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
        install_cmd="apt-get install -y"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
        install_cmd="apt-get install -y"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
        install_cmd="yum install -y"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
        install_cmd="apt-get install -y"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
        install_cmd="apt-get install -y"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
        install_cmd="yum install -y"
    else
        echo -e "${Error} 未检测到支持的操作系统，脚本将尝试以通用模式运行。"
        release="unknown"
    fi
}

check_installed_status(){
	[[ ! -e ${mtproxy_file} ]] && echo -e "${Error} MTProxy 没有安装，请检查 !" && exit 1
}

# 进程检测
check_pid(){
	PID=$(ps -ef| grep "mtg run"| grep -v "grep" | awk '{print $2}')
}

# 依赖安装与文件下载
Download(){
	echo -e "${Info} 正在为 ${release} 系统安装依赖..."
    
    # 根据系统安装依赖
    if [[ "${release}" == "alpine" ]]; then
        ${install_cmd} wget bash ca-certificates curl
    else
        ${install_cmd} wget ca-certificates curl
    fi

	if [[ ! -e "${file}" ]]; then
		mkdir -p "${file}"
	fi
	cd "${file}"
    
    # 架构检测
    local arch
    arch=$(uname -m)
    local bit=""
    
    echo -e "${Info} 检测到系统架构为: ${Green_font_prefix}${arch}${Font_color_suffix}"

	case "${arch}" in
        x86_64)  bit="amd64" ;;
        aarch64) bit="arm64" ;;
        armv7l)  bit="arm" ;;
        i386|i686) bit="386" ;;
        *)
            echo -e "${Error} 不支持的系统架构: ${arch}"
            exit 1
            ;;
    esac

	echo -e "${Info} 准备下载 MTProxy 二进制文件 (版本: v1.0.0 / 架构: ${bit})..."
    
    # 使用 GitHub 官方源
    download_url="https://github.com/9seconds/mtg/releases/download/v1.0.0/mtg-linux-${bit}"
    
    wget --no-check-certificate -O mtg "${download_url}"
    
    # 校验
	if [[ ! -e "mtg" ]]; then
		echo -e "${Error} 下载失败，文件未创建！"
		exit 1
	fi

    filesize=$(stat -c%s "mtg" 2>/dev/null || wc -c <"mtg")
    if [[ $filesize -lt 1048576 ]]; then
        echo -e "${Error} 下载文件过小 (${filesize} bytes)，可能是下载失败。"
        rm -f mtg
        exit 1
    fi
    
	chmod +x mtg
    echo -e "${Info} MTProxy 主程序安装成功！"
}

# 生成启动脚本 (核心逻辑)
Generate_Run_Script(){
    cat > ${mtproxy_run} <<EOF
#!/bin/bash
# 加载配置
source ${mtproxy_conf}

# 构建命令
CMD="${mtproxy_file} run 0.0.0.0:\${PORT} -t \${PASSWORD}"

# 如果有 NAT IPv4，添加参数 (mtg v1.0.0 语法可能略有不同，这里适配通用 run 命令)
if [[ -n "\${NAT_IPV4}" ]]; then
    # 注意：不同版本的 mtg 参数不同，v1.0.0 主要是通过 auto 识别，或者直接 bind
    # 如果是在 NAT 后面，主要影响的是分享链接生成，核心监听还是 0.0.0.0
    :
fi

if [[ -n "\${TAG}" ]]; then
    CMD="\${CMD} --adtag \${TAG}"
fi

# 写入日志并启动
echo "Starting MTProxy: \${CMD}" >> ${mtproxy_log}
exec \${CMD} >> ${mtproxy_log} 2>&1
EOF
    chmod +x ${mtproxy_run}
}

# 配置服务管理 (Systemd / OpenRC)
Service(){
    Generate_Run_Script

    if [[ "${release}" == "alpine" ]]; then
        echo -e "${Info} 检测到 Alpine Linux，正在安装 OpenRC 服务脚本..."
        cat > /etc/init.d/mtproxy-go <<EOF
#!/sbin/openrc-run
name="mtproxy-go"
description="MTProxy Go Version"
command="${mtproxy_run}"
command_background=true
pidfile="/run/mtproxy-go.pid"
output_log="${mtproxy_log}"
error_log="${mtproxy_log}"

depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/mtproxy-go
        rc-update add mtproxy-go default
        echo -e "${Info} OpenRC 服务安装完成。"

    elif command -v systemctl >/dev/null 2>&1; then
        echo -e "${Info} 检测到 Systemd，正在安装 Systemd 服务脚本..."
        cat > /etc/systemd/system/mtproxy-go.service <<EOF
[Unit]
Description=MTProxy Go Version
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${mtproxy_run}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mtproxy-go
        echo -e "${Info} Systemd 服务安装完成。"
    else
        echo -e "${Tip} 未检测到 Systemd 或 OpenRC，将使用 nohup 后台运行。"
    fi
}

# 写入配置文件 (优化格式为 Shell 变量)
Write_config(){
	cat > ${mtproxy_conf}<<EOF
PORT="${mtp_port}"
PASSWORD="${mtp_passwd}"
FAKE_TLS="${mtp_tls}"
TAG="${mtp_tag}"
NAT_IPV4="${mtp_nat_ipv4}"
NAT_IPV6="${mtp_nat_ipv6}"
SECURE="${mtp_secure}"
EOF
}

# 读取配置文件
Read_config(){
	[[ ! -e ${mtproxy_conf} ]] && echo -e "${Error} 配置文件不存在 !" && exit 1
	source ${mtproxy_conf}
}

# 设置端口
Set_port(){
    echo -e "请输入 MTProxy 端口 [1-65535] (NAT机请输入公网端口)"
    read -e -p "(默认: 443):" mtp_port
    [[ -z "${mtp_port}" ]] && mtp_port="443"
}

# 设置密码
Set_passwd(){
    echo "请输入 MTProxy 密匙"
    read -e -p "(若需要开启TLS伪装建议直接回车):" mtp_passwd
    if [[ -z "${mtp_passwd}" ]]; then
        echo -e "是否开启TLS伪装？[Y/n]"
        read -e -p "(默认：Y 启用):" mtp_tls
        [[ -z "${mtp_tls}" ]] && mtp_tls="Y"
        if [[ "${mtp_tls}" == [Yy] ]]; then
            echo -e "请输入TLS伪装域名 (例如: itunes.apple.com)"
            read -e -p "(默认：itunes.apple.com):" fake_domain
            [[ -z "${fake_domain}" ]] && fake_domain="itunes.apple.com"
            mtp_tls="YES"
            mtp_passwd=$(${mtproxy_file} generate-secret -c ${fake_domain} tls)
        else
            mtp_tls="NO"
            mtp_passwd=$(date +%s%N | md5sum | head -c 32)
        fi
    else
        mtp_tls="NO"
    fi
}

Set_tag(){
    echo "请输入 TAG (回车跳过)"
    read -e -p ":" mtp_tag
}

Set_nat(){
    echo "请输入公网 IPv4 (NAT机必填，否则回车自动检测)"
    read -e -p ":" mtp_nat_ipv4
    if [[ -z "${mtp_nat_ipv4}" ]]; then
        mtp_nat_ipv4=$(curl -s4 ip.sb || wget -qO- -4 ip.sb)
    fi
}

Install(){
    check_root
    check_sys
    Download
    echo -e "${Info} 配置参数..."
    Set_port
    Set_passwd
    Set_tag
    Set_nat
    Write_config
    Service
    Start
}

Start(){
    if [[ "${release}" == "alpine" ]]; then
        rc-service mtproxy-go restart
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart mtproxy-go
    else
        pkill -f "${mtproxy_file}"
        nohup bash ${mtproxy_run} >/dev/null 2>&1 &
    fi
    sleep 2
    check_pid
    if [[ ! -z ${PID} ]]; then
        echo -e "${Info} MTProxy 启动成功！"
        View
    else
        echo -e "${Error} MTProxy 启动失败，请查看日志：cat ${mtproxy_log}"
    fi
}

Stop(){
    if [[ "${release}" == "alpine" ]]; then
        rc-service mtproxy-go stop
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtproxy-go
    else
        pkill -f "${mtproxy_file}"
    fi
    echo -e "${Info} 已停止。"
}

View(){
    Read_config
    clear
    echo -e "MTProxy 配置信息："
    echo -e "————————————————"
    echo -e "地址\t: ${Green_font_prefix}${NAT_IPV4}${Font_color_suffix}"
    echo -e "端口\t: ${Green_font_prefix}${PORT}${Font_color_suffix}"
    echo -e "密钥\t: ${Green_font_prefix}${PASSWORD}${Font_color_suffix}"
    echo -e "链接\t: ${Red_font_prefix}tg://proxy?server=${NAT_IPV4}&port=${PORT}&secret=${PASSWORD}${Font_color_suffix}"
}

Update(){
    Download
    Start
}

Uninstall(){
    Stop
    rm -rf ${file}
    if [[ "${release}" == "alpine" ]]; then
        rm -f /etc/init.d/mtproxy-go
        rc-update del mtproxy-go default
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl disable mtproxy-go
        rm -f /etc/systemd/system/mtproxy-go.service
        systemctl daemon-reload
    fi
    echo -e "${Info} 卸载完成。"
}

# 菜单
echo && echo -e "  MTProxy-Go 全平台通用版 [Alpine/Debian/CentOS]
  
  1. 安装 (Install)
  2. 更新核心 (Update)
  3. 卸载 (Uninstall)
  4. 启动 (Start)
  5. 停止 (Stop)
  6. 查看信息 (View)
  7. 查看日志 (Log)
"
read -e -p " 请输入数字 [1-7]:" num
case "$num" in
	1) Install ;;
	2) Update ;;
	3) Uninstall ;;
	4) Start ;;
	5) Stop ;;
	6) View ;;
	7) tail -f ${mtproxy_log} ;;
	*) echo "请输入正确数字" ;;
esac
