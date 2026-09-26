#!/usr/bin/env bash
# 无网络、无系统写入；从命令入口验证参数、权限和失败处理。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source ./debian.sh
passed=0
failed=0
check() {
    local name=$1; shift
    if ( "$@" ); then printf 'PASS %s\n' "$name"; passed=$((passed+1))
    else printf 'FAIL %s\n' "$name" >&2; failed=$((failed+1)); fi
}
# 仅模拟启动时读取的发行版信息、账户与命令可用性。
function . { ID=debian; VERSION_ID=${TEST_VERSION:-12}; VERSION_CODENAME=test; }
getent() { printf 'demo:x:1000:1000::/tmp:/bin/bash\n'; }
has() { return 0; }
sudo() { [[ $1 == -v ]] && return 0; [[ $1 == -- ]] && shift; "$@"; }
args_valid() {
    set_libs() { [[ $TARGET_USER == demo && $TIMEZONE == Asia/Singapore ]]; }
    app_zsh() { :; }
    main --user demo --timezone Asia/Singapore set_init app_zsh
}
version_13() { TEST_VERSION=13; set_libs() { :; }; main set_libs; }
version_rejected() { TEST_VERSION=14; ! main set_libs; }
args_invalid() { ! main 'echo injected'; }
args_missing() { ! main --user; }
help_no_privilege() { sudo() { return 99; }; main --help >/dev/null; }
root_or_no_sudo() {
    has() { [[ $1 == apt-get ]]; }
    sudo() { return 99; }
    set_libs() { :; }
    if ((EUID == 0)); then main set_libs; else ! main set_libs; fi
}
privilege_dispatch() { [[ $(as_root printf '%s' 'ok') == ok ]]; }
apt_update_once() {
    local calls=0; APT_UPDATED=0
    as_root() { calls=$((calls+1)); }
    apt_update && apt_update && [[ $calls == 1 ]]
}
apt_failure() {
    local installed=0; APT_UPDATED=0
    as_root() { if [[ $2 == update ]]; then return 42; fi; installed=1; }
    ! apt_install curl && [[ $installed == 0 && $APT_UPDATED == 0 ]]
}
batch_failure() {
    local ran=0
    set_libs() { return 1; }; app_zsh() { ran=1; }
    ! main set_init app_zsh && [[ $ran == 0 ]]
}
libs_existing_links() {
    local calls=''
    apt_install() { [[ $1 != eza ]]; }
    apt-cache() { printf '  Candidate: (none)\n'; }
    as_user() { calls+="$1;"; [[ $1 == mkdir || $1 == test ]]; }
    set_libs && [[ $calls != *ln* ]]
}
hostname_invalid() { HOSTNAME_VALUE=-bad; require_systemd() { :; }; ! set_hostname; }
ntp_preserves_chrony() {
    local calls=''; TIMEZONE=UTC
    require_systemd() { :; }
    systemctl() { [[ $1 == is-active && $3 == chrony.service ]]; }
    apt_install() { return 99; }; as_root() { calls+="$*;"; }; timedatectl() { :; }
    set_ntp && [[ $calls == *'enable --now chrony.service'* ]]
}
ssh_invalid() {
    require_systemd() { :; }; apt_install() { :; }
    read_input() { printf -v "$2" '%s' 'not-a-key'; }
    ! set_ssh
}
check '参数与旧命令别名' args_valid
check '接受 Debian 13' version_13
check '拒绝其他发行版版本' version_rejected
check '拒绝任意命令执行' args_invalid
check '拒绝缺失参数值' args_missing
check '帮助不要求权限' help_no_privilege
check 'root 无需 sudo / 普通用户缺 sudo 明确退出' root_or_no_sudo
check '权限封装保留参数' privilege_dispatch
check 'APT 刷新去重' apt_update_once
check 'APT 失败停止安装' apt_failure
check '批量命令失败停止' batch_failure
check '保留已有链接且 eza 可选' libs_existing_links
check '拒绝非法主机名' hostname_invalid
check '保留正在运行的 chrony' ntp_preserves_chrony
check '拒绝无效公钥' ssh_invalid
printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
