#!/bin/bash

function init() {
    apt update
    apt install sudo curl wget zip unzip -y
}

function install_zsh() {
    apt install zsh git fonts-firacode -y
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
    wget http://raw.github.com/caiogondim/bullet-train-oh-my-zsh-theme/master/bullet-train.zsh-theme -O ~/.oh-my-zsh/themes/bullet-train.zsh-theme
    sudo sed -i "s/ZSH_THEME=.*/ZSH_THEME='bullet-train'/" ~/.zshrc
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    sudo sed -i "s/plugins=.*/plugins=(extract zsh-syntax-highlighting zsh-autosuggestions git)/" ~/.zshrc
    echo "source ~/.profile" >>~/.zshrc
    source ~/.zshrc
}
function install_fd() {
    #查找工具
    wget https://github.com/sharkdp/fd/releases/download/v8.2.1/fd_8.2.1_amd64.deb
    dpkg -i fd_8.2.1_amd64.deb
    rm fd_8.2.1_amd64.deb
}
function set_time() {
    sudo apt install ntp -y
    systemctl enable ntp
    sudo service ntp restart
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    date
}
init
install_zsh
install_fd
