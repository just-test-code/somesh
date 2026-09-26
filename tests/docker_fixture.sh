#!/usr/bin/env bash
# 所有系统路径重定向到临时目录；只模拟 Docker/systemd 和网络，不模拟证书生成。
fixture_setup() {
    TLS_WORK=$(mktemp -d)
    export TLS_WORK
    trap 'rm -rf -- "$TLS_WORK"' EXIT
    mkdir -p "$TLS_WORK/etc/docker"
    cd "$TLS_WORK" || return 1
    DOCKER_TLS_HOST=docker.example.com
    DOCKER_TLS_BIND=127.0.0.1
    DOCKER_TLS_YEARS=${TEST_YEARS:-1}
}
require_systemd() { :; }
apt_install() { :; }
confirm() { printf '%s\n' "$*" > "$TLS_WORK/confirmation"; return "${CONFIRM_RESULT:-0}"; }
read_input() {
    [[ -n ${MANUAL_HOST:-} ]] || return 1
    printf -v "$2" '%s' "$MANUAL_HOST"
}
curl() {
    printf '%s\n' "$*" >> "$TLS_WORK/lookups"
    case "${*: -1}" in
        https://ipinfo.io/ip) [[ ${IPINFO_FAIL:-0} == 0 ]] || return 22; printf '%s\n' "${IPINFO_RESULT:-8.8.8.8}" ;;
        https://api.ipify.org) [[ ${BACKUP_FAIL:-0} == 0 ]] || return 22; printf '%s\n' "${BACKUP_RESULT:-1.1.1.1}" ;;
        *) return 99 ;;
    esac
}
as_root() {
    local cmd=$1 arg mapped=()
    shift
    case "$cmd" in
        sh) printf '/usr/bin/dockerd\n'; return ;;
        systemctl)
            printf '%s\n' "$*" >> "$TLS_WORK/systemctl"
            case "$1" in
                show)
                    local start='/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock'
                    [[ ${TEST_DOCKER_LEGACY:-0} != 1 ]] || start='/usr/bin/dockerd -H fd:// $DOCKER_OPTS'
                    local drop="$TLS_WORK/etc/systemd/system/docker.service.d/90-somesh-tls.conf"
                    if [[ -f $drop ]]; then start=$(sed -n 's/^ExecStart=\(.\+\)$/\1/p' "$drop"); fi
                    printf '{ path=/usr/bin/dockerd ; argv[]=%s ; }\n' "${CUSTOM_EXEC:-$start}" ;;
                restart)
                    if [[ ${FAIL_RESTART:-0} == 1 && ! -e $TLS_WORK/restart-failed ]]; then
                        touch "$TLS_WORK/restart-failed"; return 1
                    fi ;;
            esac
            return 0 ;;
        /usr/bin/dockerd)
            printf '%s\n' "$*" > "$TLS_WORK/validated"
            return "${FAIL_VALIDATE:-0}" ;;
        curl)
            if [[ " $* " == *' --cert '* ]]; then printf OK; return 0; fi
            [[ ${ALLOW_ANONYMOUS:-0} == 1 ]] && return 0
            return 22 ;;
    esac
    # 只允许经过映射的文件操作，测试不调用任何真实系统管理命令。
    case "$cmd" in test|install|mktemp|openssl|tee|chmod|rm|mv|cp|grep|sed|python3|tar|cat) ;; *) echo "Unexpected command: $cmd" >&2; return 99 ;; esac
    for arg in "$@"; do
        [[ $arg == /etc/* ]] && arg="$TLS_WORK$arg"
        mapped+=("$arg")
    done
    # Git Bash 的 install -m 不能可靠应用 Windows ACL；Linux 使用原命令验证权限。
    if [[ $cmd == install && $OSTYPE == msys* ]]; then
        if [[ ${mapped[0]} == -d ]]; then mkdir -p -- "${mapped[-1]}"
        else cp -- "${mapped[-2]}" "${mapped[-1]}"; fi
        return
    fi
    "$cmd" "${mapped[@]}"
}
