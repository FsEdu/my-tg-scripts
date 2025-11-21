#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: Alpine/CentOS/Debian/Ubuntu
#	Description: MTProxy Golang (v2.1.7 Stable)
#	Version: 2.5.0-Hardcoded
#	Modified by: Gemini AI
#=================================================

sh_ver="2.5.0-Hardcoded"
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

# 检查 Root
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 请使用 Root 账号运行此脚本！" && exit 1
}

# 系统检测
check_sys(){
	if [[ -f /etc/alpine-release ]]; then
		release="alpine"
        install_cmd="apk add --no-cache"
	elif [[ -f /etc/redhat-release ]]; then
		release="centos"
        install_cmd="yum install -y"
	elif cat /etc/issue | grep -q -E -i "debian|ubuntu"; then
		release="debian"
        install_cmd="apt-get install -y"
    else
        release="unknown"
    fi
}

check_installed_status(){
	[[ ! -e ${mtproxy_file} ]] && echo -e "${Error} MTProxy 没有安装，请检查 !" && exit 1
}

check_pid(){
	PID=$(ps -ef | grep "mtg simple-run" | grep -v "grep" | awk '{print $2}')
}

# 下载与安装
Download(){
	echo -e "${Info} 正在为 ${release} 系统安装依赖..."
    
    # 强制安装 xxd 和 openssl 用于备用密码生成
    if [[ "${release}" == "alpine" ]]; then
        ${install_cmd} wget bash ca-certificates curl tar xxd openssl
    else
        ${install_cmd} wget ca-certificates curl tar vim-common openssl
    fi

	if [[ ! -e "${file}" ]]; then
		mkdir -p "${file}"
	fi
	cd "${file}"
    
    local arch
    arch=$(uname -m)
    local bit=""
    
    echo -e "${Info} 检测到系统架构为: ${Green_font_prefix}${arch}${Font_color_suffix}"

	case "${arch}" in
        x86_64)  bit="amd64" ;;
        aarch64) bit="arm64" ;;
        armv7l)  bit="armv7" ;;
        *)
            echo -e "${Error} 不支持的系统架构: ${arch}"
            exit 1
            ;;
    esac

    # 使用 v2.1.7 稳定版
    version="2.1.7"
	filename="mtg-${version}-linux-${bit}.tar.gz"
	echo -e "${Info} 准备下载 MTProxy v${version} (架构: ${bit})..."
    
    download_url="https://github.com/9seconds/mtg/releases/download/v${version}/${filename}"
    
    # 检测是否需要重新下载 (如果文件大小不对或不存在)
    need_download=true
    if [[ -e "mtg" ]]; then
        # 简单检查一下现有的 mtg 能不能跑
        ./mtg --version >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} 检测到 mtg 文件已存在且可运行，跳过下载。"
            need_download=false
        else
            echo -e "${Tip} 现有的 mtg 文件损坏或架构不符，重新下载..."
            rm -f mtg
        fi
    fi

    if [[ "$need_download" = true ]]; then
        rm -f ${filename}
        wget --no-check-certificate -O ${filename} "${download_url}"
        
        if [[ ! -e "${filename}" ]]; then
            echo -e "${Error} 下载失败，文件不存在！"
            exit 1
        fi
        
        filesize=$(stat -c%s "${filename}" 2>/dev/null || wc -c <"${filename}")
        if [[ $filesize -lt 1048576 ]]; then
            echo -e "${Error} 下载文件过小 (${filesize} bytes)，可能是下载链接失效。"
            rm -f ${filename}
            exit 1
        fi

        echo -e "${Info} 下载成功，正在解压..."
        tar -xzf ${filename} --strip-components=1
        
        if [[ ! -e "mtg" ]]; then
            find . -name "mtg" -type f -exec mv {} . \;
        fi

        if [[ ! -e "mtg" ]]; then
            echo -e "${Error} 解压失败，未找到 mtg 二进制文件！"
            exit 1
        fi
        
        chmod +x mtg
        rm -f ${filename} LICENSE README.md
        echo -e "${Info} MTProxy 主程序安装成功！"
    fi
}

# 生成启动脚本 - 核心修改：硬编码参数
Generate_Run_Script(){
    # 确保参数存在
    if [[ -z "${mtp_port}" || -z "${mtp_passwd}" ]]; then
        echo -e "${Error} 严重错误：生成启动脚本时参数丢失！"
        exit 1
    fi

    # 直接将具体的端口和密码写入文件，不使用变量引用
    cat > ${mtproxy_run} <<EOF
#!/usr/bin/env bash
echo "--- Session Start: \$(date) ---" > ${mtproxy_log}

# Debug info
echo "Executing binary with hardcoded params..." >> ${mtproxy_log}

# 启动命令 (Hardcoded)
# Port: ${mtp_port}
# Secret: ${mtp_passwd}
exec ${mtproxy_file} simple-run -b 0.0.0.0:${mtp_port} ${mtp_passwd} >> ${mtproxy_log} 2>&1
EOF
    chmod +x ${mtproxy_run}
}

# 服务管理
Service(){
    Generate_Run_Script

    if [[ "${release}" == "alpine" ]]; then
        echo -e "${Info} 安装 OpenRC 服务..."
        cat > /etc/init.d/mtproxy-go <<EOF
#!/sbin/openrc-run
name="mtproxy-go"
description="MTProxy Go v2"
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
        rc-update add mtproxy-go default >/dev/null 2>&1

    elif command -v systemctl >/dev/null 2>&1; then
        echo -e "${Info} 安装 Systemd 服务..."
        cat > /etc/systemd/system/mtproxy-go.service <<EOF
[Unit]
Description=MTProxy Go v2
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${mtproxy_run}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mtproxy-go >/dev/null 2>&1
    fi
}

# 写入配置 (仅用于 View 查看，不用于运行)
Write_config(){
	cat > ${mtproxy_conf}<<EOF
PORT="${mtp_port}"
PASSWORD="${mtp_passwd}"
FAKE_TLS="${mtp_tls}"
EOF
}

Read_config(){
	[[ ! -e ${mtproxy_conf} ]] && echo -e "${Error} 配置文件不存在 !" && exit 1
	source ${mtproxy_conf}
}

Set_port(){
    echo -e "请输入端口 (NAT机请输入公网端口)"
    read -e -p "(默认: 443):" mtp_port
    [[ -z "${mtp_port}" ]] && mtp_port="443"
}

Set_passwd(){
    echo -e "请输入伪装域名 (例如: bing.com, itunes.apple.com)"
    read -e -p "(默认: itunes.apple.com):" fake_domain
    [[ -z "${fake_domain}" ]] && fake_domain="itunes.apple.com"
    
    echo -e "${Info} 正在生成密钥..."
    
    # 尝试方法 1：使用 mtg 生成
    mtp_passwd=$(${mtproxy_file} generate-secret --hex ${fake_domain} 2>/dev/null)
    
    # 尝试方法 2：手动生成（双重保险）
    if [[ -z "${mtp_passwd}" ]]; then
        echo -e "${Tip} 二进制生成密钥失败，尝试备用方案..."
        random_hex=$(openssl rand -hex 16)
        domain_hex=$(echo -n "${fake_domain}" | xxd -p | tr -d '\n')
        mtp_passwd="ee${random_hex}${domain_hex}"
    fi
    
    if [[ -z "${mtp_passwd}" ]]; then
        echo -e "${Error} 密钥生成彻底失败，请检查系统环境！"
        exit 1
    fi
    
    echo -e "${Info} 密钥生成成功: ${mtp_passwd:0:10}..."
    mtp_tls="YES"
}

Install(){
    check_root
    check_sys
    Download
    echo -e "${Info} 配置参数..."
    Set_port
    Set_passwd
    Write_config
    Service
    Start
}

Start(){
    # 先清理日志
    > ${mtproxy_log}

    if [[ "${release}" == "alpine" ]]; then
        rc-service mtproxy-go restart
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart mtproxy-go
    else
        pkill -f "mtg simple-run"
        nohup bash ${mtproxy_run} >/dev/null 2>&1 &
    fi
    
    echo -e "${Info} 正在启动..."
    sleep 3
    check_pid
    if [[ ! -z ${PID} ]]; then
        echo -e "${Info} MTProxy 启动成功！(PID: ${PID})"
        View
    else
        echo -e "${Error} 启动失败，正在读取最新日志..."
        echo -e "================ 日志开始 ================"
        cat ${mtproxy_log}
        echo -e "================ 日志结束 ================"
        echo -e "${Tip} 如果日志显示 'bind: address already in use'，请换个端口重装。"
        echo -e "${Tip} 正在检查生成的启动脚本内容 (用于调试):"
        cat ${mtproxy_run}
    fi
}

Stop(){
    if [[ "${release}" == "alpine" ]]; then
        rc-service mtproxy-go stop
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtproxy-go
    else
        pkill -f "mtg simple-run"
    fi
    echo -e "${Info} 已停止。"
}

View(){
    Read_config
    public_ip=$(curl -s4 ip.sb || wget -qO- -4 ip.sb)
    
    clear
    echo -e "MTProxy v2 配置信息 (硬编码模式)："
    echo -e "————————————————"
    echo -e "地址\t: ${Green_font_prefix}${public_ip}${Font_color_suffix}"
    echo -e "端口\t: ${Green_font_prefix}${mtp_port}${Font_color_suffix}"
    echo -e "密钥\t: ${Green_font_prefix}${mtp_passwd}${Font_color_suffix}"
    echo -e "链接\t: ${Red_font_prefix}tg://proxy?server=${public_ip}&port=${mtp_port}&secret=${mtp_passwd}${Font_color_suffix}"
    echo -e "注意：如果是 NAT 机，请确保 '端口' 填写的是服务商分配给你的公网端口。"
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
echo && echo -e "  MTProxy-Go 硬核修复版 (V2.5.0)
  
  1. 安装 (Install)
  2. 卸载 (Uninstall)
  3. 启动 (Start)
  4. 停止 (Stop)
  5. 查看信息 (View)
  6. 查看日志 (Log)
"
read -e -p " 请输入数字 [1-6]:" num
case "$num" in
	1) Install ;;
	2) Uninstall ;;
	3) Start ;;
	4) Stop ;;
	5) View ;;
	6) tail -f ${mtproxy_log} ;;
	*) echo "请输入正确数字" ;;
esac
