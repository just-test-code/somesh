#!/bin/bash

#日志类开始

decorate(){
    echo -e $@
}

gray() {
    echo -e "\033[90m$@\033[39m"
}

red(){
    echo -e "\033[91m$@\033[39m"
}

green(){
    echo -e "\033[92m$@\033[39m"
}

yellow(){
    echo -e "\033[93m$@\033[39m"
}

blue(){
    echo -e "\033[94m$@\033[39m"
}

magenta(){
    echo -e "\033[95m$@\033[39m"
}

cyan(){
    echo -e "\033[96m$@\033[39m"
}

light_gray() {
    echo -e "\033[97m$@\033[39m"
}

black() {
    echo -e "\033[30m$@\033[39m"
}

dark_red(){
    echo -e "\033[31m$@\033[39m"
}

dark_green(){
    echo -e "\033[32m$@\033[39m"
}

dark_yellow(){
    echo -e "\033[33m$@\033[39m"
}

dark_blue(){
    echo -e "\033[34m$@\033[39m"
}

dark_magenta(){
    echo -e "\033[35m$@\033[39m"
}

dark_cyan(){
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

#全局变量
fd_ver='8.4.0'
ssh_cert="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAr0xdTps65qvyHbwXks6Ik219y9nOa6oono1YQR20Gb03Gh8OOMLM/bijGsyNlI0Lh5ccwEexUGK1IvpLGqAty14wFPjvgYc5x6xOURuvuxSEgmKxNHsX97smIWvKqt8n6kOyjLSaGnbMT8KpNCTWy7IblhiJc8TvDh3LrXMMsCazX3T7n/nF4B1trQSESxsePir2UUrovm0LT2Z4F1nnFRMyEhOvie3EMqxG8XA/n463spHHMrtBpfCh+zcMijS7vt7W5fhFn+7GIngNfjWXHqkmEOXqzJ/WuNzDxbLMXUf5vsyovnHTMvaMpfjW+dzhHIWyBlRuxO6E7f/XAwLzmQ== root"

set_swapfile() {
    e_warning 配置虚拟内存
    Mem=`free -m | awk '/Mem:/{print $2}'`
    Swap=`free -m | awk '/Swap:/{print $2}'`
    if [ "$Swap" == '0' ]; then
        if [ $Mem -le 1024 ]; then
            MemCount=1024
        elif [ $Mem -gt 1024 ]; then
            MemCount=2048
        fi
        dd if=/dev/zero of=/swapfile count=$MemCount bs=1M
        mkswap /swapfile
        swapon /swapfile
        chmod 600 /swapfile
        [ -z "`grep swapfile /etc/fstab`" ] && echo '/swapfile    swap    swap    defaults    0 0' >> /etc/fstab
        e_success 虚拟内存设置完毕 $MemCount
    fi
    e_warning 虚拟内存无需配置
    
}

set_apt(){
    e_warning 修改更新源
    cat>"/etc/apt/sources.list"<<EOF
deb http://deb.debian.org/debian bullseye main
deb-src http://deb.debian.org/debian bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main
deb http://deb.debian.org/debian bullseye-updates main
deb-src http://deb.debian.org/debian bullseye-updates main
deb http://deb.debian.org/debian bullseye-backports main
deb-src http://deb.debian.org/debian bullseye-backports main
EOF
    e_warning 更新系统
    apt update
    e_warning 安装常用库
    apt install sudo curl wget unzip zip jq lrzsz -y
}

set_ssh(){
    e_warning "配置密钥登陆并禁用密码登录"
    mkdir /root/.ssh
    sudo echo $ssh_cert | cat > /root/.ssh/authorized_keys
    sudo chmod 600 /root/.ssh/authorized_keys
    sudo sed -i '/Protocol/d' /etc/ssh/sshd_config
    sudo echo "Protocol 2" >> /etc/ssh/sshd_config
    sudo sed -i "s/.*RSAAuthentication.*/RSAAuthentication yes/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*AuthorizedKeysFile.*/AuthorizedKeysFile\t\.ssh\/authorized_keys/g" /etc/ssh/sshd_config
    sudo sed -i "s/.*PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
    sudo service sshd restart
    e_success "密钥配置完成"
}

set_ntp(){
    e_warning 安装时间同步ntp
    apt install ntp -y
    systemctl enable ntp
    sudo service ntp restart
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    date
}


app_docker(){
    e_warning 开始安装Docker
    curl -fsSL https://get.docker.com | bash -s docker
    e_warning 开始安装Docker-compose
    compose_ver=$(wget -qO- -t1 -T2 "https://api.github.com/repos/docker/compose/releases/latest" | jq -r '.tag_name')
    sudo curl -L "https://github.com/docker/compose/releases/download/$compose_ver/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    e_success Docker安装完毕
}
app_fd(){
    e_warning 开始安装fd
    wget https://github.com/sharkdp/fd/releases/download/v$fd_ver/fd_${fd_ver}_amd64.deb
    dpkg -i fd_${fd_ver}_amd64.deb
    rm fd_${fd_ver}_amd64.deb
    e_success fd安装完毕
}
app_zsh(){
    apt install zsh git fonts-firacode -y
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended
    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
    wget http://raw.github.com/caiogondim/bullet-train-oh-my-zsh-theme/master/bullet-train.zsh-theme -O ~/.oh-my-zsh/themes/bullet-train.zsh-theme
    sudo sed -i "s/ZSH_THEME=.*/ZSH_THEME='bullet-train'/" ~/.zshrc
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    sudo sed -i "s/plugins=.*/plugins=(extract zsh-syntax-highlighting zsh-autosuggestions git)/" ~/.zshrc
    echo "source ~/.profile" >>~/.zshrc
    chsh -s /bin/zsh
    zsh
    #source ~/.zshrc
}
e_error 开始执行脚本
for i in "$@"; do
    $i
done
e_error 脚本执行完毕


