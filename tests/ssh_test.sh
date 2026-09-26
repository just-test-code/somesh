#!/usr/bin/env bash
# 公钥解析只模拟成功结果；实际配置文件在临时目录，服务调用全部模拟。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./debian.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
require_systemd() { :; }
apt_install() { :; }
ssh-keygen() { return 0; }
as_user() { "$@"; }
confirm() { printf '%s\n' "$*" > "$work/prompt"; return "$ANSWER"; }
as_root() {
    local cmd=$1 arg mapped=(); shift
    case "$cmd" in
        /usr/sbin/sshd)
            if [[ $1 == -t ]]; then
                if [[ $MODE == invalid ]] && grep -q 'BEGIN somesh' "$work/sshd_config"; then return 1; fi
            else printf 'pubkeyauthentication yes\npasswordauthentication no\nkbdinteractiveauthentication no\n'; fi
            return 0 ;;
        systemctl)
            if [[ $1 == reload ]]; then
                printf 'reload\n' >> "$work/reloads"
                if [[ $MODE == reload-fails && ! -e $work/failed ]]; then touch "$work/failed"; return 1; fi
            fi
            return 0 ;;
        cp|sed) ;;
        *) return 99 ;;
    esac
    for arg in "$@"; do
        [[ $arg != /etc/ssh/sshd_config* ]] || arg="$work/${arg##*/}"
        mapped+=("$arg")
    done
    "$cmd" "${mapped[@]}"
}
TARGET_USER=demo
TARGET_HOME="$work/home"
SSH_KEY_FILE="$work/key.pub"
printf 'ssh-ed25519 fake-test-key test\n' > "$SSH_KEY_FILE"
mkdir -p "$TARGET_HOME/.ssh"
for MODE in decline accept invalid reload-fails; do
    ANSWER=0; [[ $MODE != decline ]] || ANSWER=1
    printf 'PasswordAuthentication yes\n' > "$work/sshd_config"
    printf 'old-key\n' > "$TARGET_HOME/.ssh/authorized_keys"
    rm -f "$work/prompt" "$work/reloads" "$work/failed"
    if [[ $MODE == invalid || $MODE == reload-fails ]]; then
        if set_ssh; then echo "FAIL $MODE succeeded"; exit 1; fi
    else set_ssh; fi
    grep -qx old-key "$TARGET_HOME/.ssh/authorized_keys"
    grep -qxF 'ssh-ed25519 fake-test-key test' "$TARGET_HOME/.ssh/authorized_keys"
    grep -q '是否现在关闭' "$work/prompt"
    if [[ $MODE == accept ]]; then
        grep -qx 'PasswordAuthentication no' "$work/sshd_config"
        [[ -f $work/reloads ]]
    else
        [[ $(cat "$work/sshd_config") == 'PasswordAuthentication yes' ]]
        if [[ $MODE == decline ]]; then [[ ! -e $work/reloads ]]; fi
    fi
done
printf 'PASS SSH follow-up: decline, accept, validation rollback and reload rollback\n'
