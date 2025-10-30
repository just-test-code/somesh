#!/bin/bash

#日志类开始

decorate() {
    echo -e $@
}

gray() {
    echo -e "\033[90m$@\033[39m"
}

red() {
    echo -e "\033[91m$@\033[39m"
}

green() {
    echo -e "\033[92m$@\033[39m"
}

yellow() {
    echo -e "\033[93m$@\033[39m"
}

blue() {
    echo -e "\033[94m$@\033[39m"
}

magenta() {
    echo -e "\033[95m$@\033[39m"
}

cyan() {
    echo -e "\033[96m$@\033[39m"
}

light_gray() {
    echo -e "\033[97m$@\033[39m"
}

black() {
    echo -e "\033[30m$@\033[39m"
}

dark_red() {
    echo -e "\033[31m$@\033[39m"
}

dark_green() {
    echo -e "\033[32m$@\033[39m"
}

dark_yellow() {
    echo -e "\033[33m$@\033[39m"
}

dark_blue() {
    echo -e "\033[34m$@\033[39m"
}

dark_magenta() {
    echo -e "\033[35m$@\033[39m"
}

dark_cyan() {
    echo -e "\033[36m$@\033[39m"
}

white() {
    echo -e "\033[37m$@\033[39m"
}

light_purple() {
    if [[ -z $_PURPLE ]]; then
        _PURPLE=$(tput setaf 171)
    fi
    echo -e "${_PURPLE}$@\033[39m"
}

light_blue() {
    if [[ -z $_BLUE ]]; then
        _BLUE=$(tput setaf 38)
    fi
    echo -e "${_BLUE}$@\033[39m"
}

# export -f decorate
# export -f red
# export -f green
# export -f yellow
# export -f blue
# export -f magenta
# export -f cyan
# export -f dark_red
# export -f dark_green
# export -f dark_yellow
# export -f dark_blue
# export -f dark_magenta
# export -f dark_cyan

# Color variables

bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 76)
tan=$(tput setaf 3)

Bold="\033[1m"
Dim="\033[2m"
Underlined="\033[4m"
Blink="\033[5m"
Reverse="\033[7m"
Hidden="\033[8m"

ResetBold="\033[21m"
ResetDim="\033[22m"
ResetUnderlined="\033[24m"
ResetBlink="\033[25m"
ResetReverse="\033[27m"
ResetHidden="\033[28m"

# Log functions
# Usage:
# e_header "ArchLinux Installation"

e_header() {
    light_purple "========== $@ =========="
}
e_arrow() {
    echo "==========|| ➜ $@ ||=========="
}

e_success() {
    green "==========|| ✔ $@ ||=========="
}
e_error() {
    dark_red "==========|| ✖ $@ ||=========="
}
e_warning() {
    dark_yellow $(e_arrow "$@")
}
e_underline() {
    printf "${underline}%s${reset}\n" "$@"
}
e_bold() {
    printf "${bold}%s${reset}\n" "$@"
}
e_note() {
    light_blue "${Underlined}${Bold}Note:${ResetBold}${ResetUnderlined} $@"
}

# has: Check if executable exist
# Usage:
# has tput
# has bash
# has foo
has() {
    if [[ $(type $1) = *"is"* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Step function
# Usage:
# e_reset_step
# e_step "Install requirements"
# e_step "Install binaries"
# e_reset_step
# e_step "Another step"
e_step() {
    if [[ -z $_DE_COLOR ]]; then
        export _DE_COLOR="\033[39m"
    fi
    if [[ -z $_UNDERLINE ]]; then
        export _UNDERLINE="\033[4m"
        export _DE_UNDERLINE="\033[24m"
    fi
    if [[ -z $_BLUE ]]; then
        if [[ $(has tput) = "true" ]]; then
            _BLUE=$(tput setaf 38)
        else
            _BLUE="\033[94m"
        fi
    fi
    echo -en "${_UNDERLINE}${_BLUE}Step"
    # if [[ $(has expr) ]]; then
    export E_STEP=${E_STEP:-1}
    echo -en " $E_STEP"
    export E_STEP=$((E_STEP + 1))
    # fi
    echo -e ".${_DE_COLOR}${_DE_UNDERLINE} $@"
}

e_reset_step() {
    export E_STEP=
}

# Indent strings
# Usage:
# echo "haha" | indent 2
# cat file.txt | indent 1 4

indent() {
    local indentCount=1
    local indentWidth=2
    if [[ -n "$1" ]]; then indentCount=$1; fi
    if [[ -n "$2" ]]; then indentWidth=$2; fi
    pr -to $((indentCount * indentWidth))
}

eecho() {
    echo "$@" 1>&2
}

#日志类结束

# 检查 sudo 权限
check_sudo() {
    e_warning "检查 sudo 权限..."

    # 检查是否为 root 用户
    if [ "$EUID" -eq 0 ]; then
        e_success "当前以 root 用户运行"
        return 0
    fi

    # 检查是否安装了 sudo
    if ! command -v sudo &> /dev/null; then
        e_error "系统未安装 sudo，请先安装 sudo 或使用 root 用户运行"
        exit 1
    fi

    # 测试 sudo 权限
    if sudo -n true 2>/dev/null; then
        e_success "sudo 权限验证成功（无需密码）"
        return 0
    fi

    # 需要输入密码
    e_warning "此脚本需要 sudo 权限，请输入密码"
    if sudo -v; then
        e_success "sudo 权限验证成功"
        # 保持 sudo 会话活跃
        while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
        return 0
    else
        e_error "sudo 权限验证失败，脚本退出"
        exit 1
    fi
}

#全局变量
fd_ver='10.1.0'

set_swapfile() {
    e_warning 配置虚拟内存
    Mem=$(free -m | awk '/Mem:/{print $2}')
    Swap=$(free -m | awk '/Swap:/{print $2}')
    if [ "$Swap" == '0' ]; then
        if [ $Mem -le 1024 ]; then
            MemCount=1024
        elif [ $Mem -gt 1024 ]; then
            MemCount=2048
        fi
        sudo dd if=/dev/zero of=/swapfile count=$MemCount bs=1M
        sudo mkswap /swapfile
        sudo swapon /swapfile
        sudo chmod 600 /swapfile
        [ -z "$(grep swapfile /etc/fstab)" ] && echo '/swapfile    swap    swap    defaults    0 0' | sudo tee -a /etc/fstab
        e_success 虚拟内存设置完毕 $MemCount
    else
        e_warning 虚拟内存无需配置
    fi
}

set_init() {
    e_warning 初始化系统
    sudo apt update
    e_warning 更新系统
    sudo apt update
    e_warning 安装常用库
    sudo apt install sudo curl wget unzip zip jq lrzsz tmux fonts-firacode -y
}

set_ssh() {
    e_warning "配置密钥登陆并禁用密码登录"
    if [ -z "${ssh_cert}" ]; then
        echo "变量 ssh_cert 不存在，停止执行"
        exit 1
    fi
    [ ! -d "/root/.ssh" ] && sudo mkdir "/root/.ssh"
    echo "${ssh_cert}" | sudo tee /root/.ssh/authorized_keys
    sudo chmod 600 /root/.ssh/authorized_keys
    sudo sed -i '/Protocol/d' /etc/ssh/sshd_config
    echo "Protocol 2" | sudo tee -a /etc/ssh/sshd_config
    sudo sed -i "s/.*RSAAuthentication.*/RSAAuthentication yes/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*AuthorizedKeysFile.*/AuthorizedKeysFile\t\.ssh\/authorized_keys/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
    sudo service sshd restart
    e_success "密钥配置完成"
}

set_ntp() {
    e_warning 安装时间同步ntp
    sudo apt install ntp -y
    sudo systemctl enable ntp
    sudo service ntp restart
    sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    date
}

set_clean() {
    e_warning 一键清理垃圾
    bash <(curl -s https://raw.githubusercontent.com/JustTestCode/somesh/main/server_cleanup.sh)
    sudo apt autoremove --purge
    sudo apt clean
    sudo apt autoclean
    sudo apt remove --purge $(dpkg -l | awk '/^rc/ {print $2}')
    sudo journalctl --rotate
    sudo journalctl --vacuum-time=1s
    sudo journalctl --vacuum-size=50M
    sudo apt remove --purge $(dpkg -l | awk '/^ii linux-(image|headers)-[^ ]+/{print $2}' | grep -v $(uname -r | sed 's/-.*//') | xargs)
}

set_update() {
    e_warning 一键纯净更新
    sudo apt update -y
    sudo apt full-upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean -y
}

app_docker() {
    e_warning 开始安装Docker
    curl -fsSL https://get.docker.com | sudo bash -s docker
    # e_warning 开始安装Docker-compose
    # compose_ver=$(wget -qO- -t1 -T2 "https://api.github.com/repos/docker/compose/releases/latest" | jq -r '.tag_name')
    # curl -L "https://github.com/docker/compose/releases/download/$compose_ver/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    # sudo chmod +x /usr/local/bin/docker-compose
    # sudo ln -s /usr/local/bin/docker-compose /usr/bin/dc
    e_success Docker安装完毕
}

app_zsh() {
    e_warning 开始安装ZSH
    if ! sudo apt install zsh git fonts-firacode -y; then
        e_error "ZSH安装失败"
        return 1
    fi

    e_warning 开始安装oh-my-zsh
    if ! curl -fsSL --max-time 30 https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh | sh -s -- --unattended; then
        e_error "oh-my-zsh安装失败"
        return 1
    fi

    if [ ! -f ~/.oh-my-zsh/templates/zshrc.zsh-template ]; then
        e_error "zsh模板文件不存在"
        return 1
    fi

    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc

    if ! wget --timeout=30 http://raw.github.com/caiogondim/bullet-train-oh-my-zsh-theme/master/bullet-train.zsh-theme -O ~/.oh-my-zsh/themes/bullet-train.zsh-theme; then
        e_error "主题下载失败"
        return 1
    fi

    sed -i "s/ZSH_THEME=.*/ZSH_THEME='bullet-train'/" ~/.zshrc

    if ! git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions; then
        e_error "自动补全插件安装失败"
        return 1
    fi

    if ! git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting; then
        e_error "语法高亮插件安装失败"
        return 1
    fi

    sed -i "s/plugins=.*/plugins=(extract zsh-syntax-highlighting zsh-autosuggestions git)/" ~/.zshrc
    echo "source ~/.profile" >>~/.zshrc

    e_warning 设置zsh为默认shell
    sudo chsh -s /bin/zsh
    e_success "ZSH安装完成！请手动执行：zsh 和 source ~/.zshrc"
}

app_netclient() {
    curl -sL 'https://apt.netmaker.org/gpg.key' | sudo tee /etc/apt/trusted.gpg.d/netclient.asc
    curl -sL 'https://apt.netmaker.org/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/netclient.list
    sudo apt update
    sudo apt install netclient -y
    sudo systemctl enable netclient
    sudo systemctl start netclient
}

clean_log() {
    e_warning "开始清理系统日志"
    local log_files=(
        "/var/log/wtmp"
        "/var/log/btmp"
        "/var/log/lastlog"
        "/var/log/secure"
        "/var/log/messages"
        "/var/log/syslog"
        "/var/log/xferlog"
        "/var/log/auth.log"
        "/var/log/user.log"
        "/var/adm/sylog"
        "/var/log/maillog"
        "/var/log/openwebmail.log"
        "/var/log/mail.info"
        "/var/run/utmp"
    )

    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            if sudo bash -c ": >$log_file"; then
                e_success "已清理: $log_file"
            else
                e_error "清理失败: $log_file"
            fi
        fi
    done

    if [ -f ~/.bash_history ]; then
        : >~/.bash_history
        e_success "已清理: ~/.bash_history"
    fi

    history -c
    e_success "历史记录已清理"
}

set_hostname() {
    e_warning "修改主机名"
    echo -e "$(yellow '请输入新的主机名：')"
    read -r new_hostname
    if [ -z "$new_hostname" ]; then
        echo -e "$(red '错误：主机名不能为空')"
        sleep 2
        return
    fi
    # 验证主机名格式（只允许字母、数字、连字符）
    if [[ ! $new_hostname =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo -e "$(red '错误：主机名只能包含字母、数字和连字符')"
        sleep 2
        return
    fi
    sudo hostnamectl set-hostname "$new_hostname"
    sudo systemctl restart systemd-hostnamed
    e_success "主机名已修改为：$new_hostname"
}

# 交互式菜单函数
show_menu() {
    # 定义菜单选项
    options=(
        "设置交换文件 (set_swapfile)"
        "初始化系统配置 (set_init)"
        "配置SSH (set_ssh)"
        "配置NTP时间同步 (set_ntp)"
        "清理系统 (set_clean)"
        "更新系统 (set_update)"
        "安装Docker (app_docker)"
        "安装ZSH (app_zsh)"
        "安装NetClient (app_netclient)"
        "清理日志 (clean_log)"
        "修改主机名 (set_hostname)"
        "退出"
    )

    # 当前选中的选项索引
    current=0

    # 清屏
    clear

    # 显示菜单的函数
    function print_menu {
        local i=0
        echo -e "\n$(blue '请使用上下方向键选择要执行的操作，按回车确认：')\n"
        for item in "${options[@]}"; do
            if [ $i -eq $current ]; then
                echo -e "$(cyan '→') $(green "$item")"
            else
                echo "  $item"
            fi
            ((i++))
        done
    }

    # 执行选中的功能
    function execute_option {
        clear
        case $1 in
        0) set_swapfile ;;
        1) set_init ;;
        2) # 配置SSH
            echo -e "$(yellow '请输入SSH公钥（以ed25519或rsa开头的完整公钥字符串）：')"
            read -r ssh_cert
            if [ -z "$ssh_cert" ]; then
                echo -e "$(red '错误：SSH公钥不能为空')"
                sleep 2
                return
            fi
            # 验证公钥格式
            if [[ ! $ssh_cert =~ ^(ssh-ed25519|ssh-rsa) ]]; then
                echo -e "$(red '错误：无效的SSH公钥格式')"
                sleep 2
                return
            fi
            set_ssh
            ;;
        3) set_ntp ;;
        4) set_clean ;;
        5) set_update ;;
        6) app_docker ;;
        7) app_zsh ;;
        8) app_netclient ;;
        9) clean_log ;;
        10) set_hostname ;;
        11) exit 0 ;;
        esac
        echo -e "\n$(yellow '按任意键返回主菜单...')"
        read -n 1
    }

    # 捕获键盘输入
    while true; do
        print_menu
        read -rsn1 key
        case "$key" in
        $'\x1B') # ESC键的ASCII码
            read -rsn2 key
            case "$key" in
            "[A") # 上箭头
                if [ $current -gt 0 ]; then
                    ((current--))
                fi
                ;;
            "[B") # 下箭头
                if [ $current -lt $((${#options[@]} - 1)) ]; then
                    ((current++))
                fi
                ;;
            esac
            ;;
        "") # 回车键
            execute_option $current
            ;;
        esac
        clear
    done
}

e_header "欢迎使用服务器管理脚本"

# 检查并要求 sudo 权限
check_sudo

if [ $# -eq 0 ]; then
    show_menu
else
    for i in "$@"; do
        $i
    done
fi
e_header "脚本执行完毕"
