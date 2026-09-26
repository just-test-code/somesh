#!/usr/bin/env bash
# 对完整 Docker TLS 入口做地址选择测试，在确认前停止，绝不访问网络或修改系统。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./debian.sh
source ./tests/docker_fixture.sh
passed=0
check() {
    local name=$1; shift
    if ( fixture_setup; CONFIRM_RESULT=1; "$@" ); then
        printf 'PASS %s\n' "$name"; passed=$((passed+1))
    else printf 'FAIL %s\n' "$name" >&2; exit 1; fi
}
expect_host() {
    if docker_tcp_tls; then return 1; fi
    grep -qF "tcp://$1:2376" "$TLS_WORK/confirmation"
}
ipinfo_first() {
    DOCKER_TLS_HOST=''
    expect_host 8.8.8.8 && [[ $(wc -l < "$TLS_WORK/lookups") == 1 ]] &&
        grep -qF -- '--noproxy *' "$TLS_WORK/lookups"
}
fallback_error() { DOCKER_TLS_HOST=''; IPINFO_FAIL=1; expect_host 1.1.1.1; }
fallback_invalid() { DOCKER_TLS_HOST=''; IPINFO_RESULT='<html>error</html>'; expect_host 1.1.1.1; }
explicit_no_lookup() { expect_host docker.example.com && [[ ! -e $TLS_WORK/lookups ]]; }
manual_fallback() { DOCKER_TLS_HOST=''; IPINFO_FAIL=1; BACKUP_FAIL=1; MANUAL_HOST=manual.example.com; expect_host manual.example.com; }
no_terminal() { DOCKER_TLS_HOST=''; IPINFO_FAIL=1; BACKUP_FAIL=1; ! docker_tcp_tls && [[ ! -e $TLS_WORK/confirmation ]]; }
invalid_public() {
    DOCKER_TLS_HOST=''
    BACKUP_FAIL=1
    local address
    for address in 127.0.0.1 10.0.0.1 100.64.0.1 0.0.0.0 224.0.0.1 999.1.1.1 ::1 $'8.8.8.8\nDNS:evil.com'; do
        IPINFO_RESULT=$address
        if docker_tcp_tls; then return 1; fi
        [[ ! -e $TLS_WORK/confirmation ]] || return 1
    done
}
invalid_explicit() {
    local host
    for host in 'https://example.com' 'example.com:2376' '999.1.1.1' '0.0.0.0' $'good.com\nDNS:evil.com' '-bad.com'; do
        DOCKER_TLS_HOST=$host
        if docker_tcp_tls; then return 1; fi
        [[ ! -e $TLS_WORK/confirmation ]] || return 1
    done
    DOCKER_TLS_HOST=docker.example.com; DOCKER_TLS_BIND='0.0.0.0;evil'
    ! docker_tcp_tls && [[ ! -e $TLS_WORK/confirmation ]]
}
config_conflict() {
    printf '{"hosts": ["tcp://0.0.0.0:2375"]}' > "$TLS_WORK/etc/docker/daemon.json"
    ! docker_tcp_tls && [[ ! -e $TLS_WORK/confirmation ]]
}
custom_exec() { CUSTOM_EXEC='/usr/bin/dockerd --debug'; ! docker_tcp_tls && [[ ! -e $TLS_WORK/confirmation ]]; }
years_prompt() {
    DOCKER_TLS_YEARS=''
    read_input() { printf -v "$2" '%s' 5; }
    expect_host docker.example.com && grep -qF '证书 5 年' "$TLS_WORK/confirmation"
}
years_invalid() { DOCKER_TLS_YEARS=2; ! docker_tcp_tls && [[ ! -e $TLS_WORK/confirmation ]]; }
check 'ipinfo 优先并绕过代理' ipinfo_first
check '查询失败使用备用服务' fallback_error
check '无效响应使用备用服务' fallback_invalid
check '显式地址不联网查询' explicit_no_lookup
check '手动输入回退' manual_fallback
check '无终端停止' no_terminal
check '拒绝非法公网地址' invalid_public
check '拒绝非法连接及绑定地址' invalid_explicit
check '保留已有 daemon.json 冲突配置' config_conflict
check '拒绝覆盖自定义启动参数' custom_exec
check '交互选择五年有效期' years_prompt
check '拒绝非预设有效期' years_invalid
printf '%s checks passed\n' "$passed"
