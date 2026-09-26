#!/usr/bin/env bash
# Debian 12/13 服务器管理工具。系统操作通过 as_root，用户文件通过 as_user。
# 不使用 set -e：菜单需要处理失败并继续；每个关键步骤显式检查返回值。
set -o pipefail

APT_UPDATED=0
TARGET_USER=''
TARGET_HOME=''
TIMEZONE='Asia/Shanghai'
SSH_KEY_FILE=''
HOSTNAME_VALUE=''
DOCKER_TLS_HOST=''
DOCKER_TLS_BIND='0.0.0.0'
TTY_FD=''

log() { printf '[%s] %s\n' "$1" "$2" >&2; }
has() { command -v "$1" >/dev/null 2>&1; }

is_command() {
    case "$1" in
        set_libs|set_swapfile|set_ssh|harden_ssh|set_ntp|set_hostname|set_update|set_clean|clean_log|app_docker|docker_tcp_tls|app_zsh|install_sudo) return 0 ;;
        *) return 1 ;;
    esac
}

as_root() {
    if ((EUID == 0)); then "$@"; else sudo -- "$@"; fi
}

as_user() {
    if [[ $(id -un) == "$TARGET_USER" ]]; then
        env HOME="$TARGET_HOME" "$@"
    elif ((EUID == 0)); then
        /usr/sbin/runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" "$@"
    else
        sudo -H -u "$TARGET_USER" -- env HOME="$TARGET_HOME" "$@"
    fi
}

read_input() {
    local prompt=$1 variable=$2
    if [[ -z $TTY_FD ]]; then
        if ! { exec {TTY_FD}<>/dev/tty; } 2>/dev/null; then
            TTY_FD=''; log ERROR '此操作需要交互终端；请使用对应参数或在终端运行'; return 1
        fi
    fi
    printf '%s' "$prompt" >&"$TTY_FD"
    IFS= read -r -u "$TTY_FD" "$variable"
}

confirm() {
    local answer
    read_input "$1 [y/N] " answer || return 1
    [[ $answer == y || $answer == Y ]]
}

require_systemd() {
    [[ -d /run/systemd/system ]] && has systemctl || {
        log ERROR '当前环境没有运行 systemd，此功能需在完整 Debian 主机中执行'; return 1;
    }
}

apt_update() {
    if ((APT_UPDATED == 0)); then
        as_root apt-get update || return 1
        APT_UPDATED=1
    fi
}

apt_install() {
    apt_update || return 1
    as_root apt-get install -y -- "$@"
}

install_sudo() { apt_install sudo; }

set_libs() {
    apt_install ca-certificates curl wget unzip zip jq lrzsz tmux fonts-firacode \
        fd-find ripgrep bat gnupg git zoxide || return 1
    local pair source name dest candidate
    as_user mkdir -p -- "$TARGET_HOME/.local/bin" || return 1
    for pair in fdfind:fd batcat:bat; do
        source=${pair%:*}; name=${pair#*:}; dest="$TARGET_HOME/.local/bin/$name"
        if as_user test -e "$dest" || as_user test -L "$dest"; then
            log INFO "保留已有文件或链接：$dest"
        else
            as_user ln -s -- "/usr/bin/$source" "$dest" || return 1
        fi
    done
    candidate=$(LC_ALL=C apt-cache policy eza | awk '/Candidate:/ {print $2; exit}') || return 1
    if [[ -n $candidate && $candidate != '(none)' ]]; then
        apt_install eza || return 1
    else
        log WARN '当前软件源没有 eza（Debian 12 标准源通常没有）；已跳过该可选工具。'
        log WARN '如需 eza，请配置支持当前发行版的可信软件源后重新运行。'
    fi
    log INFO '工具安装完成；使用 fd/bat 短命令需将 ~/.local/bin 加入 PATH。'
}

set_swapfile() {
    local mem size available fs active
    active=$(as_root swapon --show --noheadings) || return 1
    if [[ -n $active ]]; then log INFO '已有活动 swap，无需创建'; return 0; fi
    if as_root test -e /swapfile || as_root test -L /swapfile; then
        log ERROR '/swapfile 已存在但未启用；请检查后手动处理，脚本不会覆盖'; return 1
    fi
    if awk '$1 == "/swapfile" {found=1} END {exit !found}' /etc/fstab; then
        log ERROR 'fstab 已包含 /swapfile，但文件不存在；请先修复该配置'; return 1
    fi
    fs=$(stat -f -c %T /) || return 1
    case "$fs" in
        ext2/ext3|xfs) ;;
        *) log ERROR "文件系统 $fs 需要专门的 swap 创建方式，已停止"; return 1 ;;
    esac
    mem=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
    [[ $mem =~ ^[0-9]+$ ]] || return 1
    size=2048
    ((mem <= 1024)) && size=1024
    available=$(df -Pm / | awk 'NR==2 {print $4}')
    [[ $available =~ ^[0-9]+$ ]] && ((available > size + 512)) || {
        log ERROR '磁盘空间不足，需额外保留至少 512 MiB'; return 1;
    }
    # noclobber 防止覆盖并发创建的文件，umask 保证文件从创建起即为 0600。
    as_root bash -c 'umask 077; set -C; : > /swapfile' || return 1
    if ! as_root dd if=/dev/zero of=/swapfile bs=1M count="$size" status=progress conv=notrunc ||
       ! as_root mkswap /swapfile || ! as_root swapon /swapfile; then
        as_root rm -f -- /swapfile
        log ERROR 'swap 创建失败，已清理本次文件'; return 1
    fi
    if ! as_root cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S).$$" ||
       ! printf '/swapfile none swap sw 0 0\n' | as_root tee -a /etc/fstab >/dev/null; then
        log WARN 'swap 已启用，但持久化失败；请检查 /etc/fstab'; return 1
    fi
    log INFO "已启用 ${size} MiB swap"
}

set_ssh() {
    local key temp auth="$TARGET_HOME/.ssh/authorized_keys"
    require_systemd || return 1
    apt_install openssh-server || return 1
    if [[ -n $SSH_KEY_FILE ]]; then
        [[ -r $SSH_KEY_FILE ]] || { log ERROR '公钥文件不可读'; return 1; }
        key=$(cat -- "$SSH_KEY_FILE") || return 1
    else
        read_input '请输入完整 SSH 公钥：' key || return 1
    fi
    [[ $key != *$'\n'* && $key =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]] ]] || {
        log ERROR '请输入单行 OpenSSH 公钥，不接受私钥或 authorized_keys 选项'; return 1;
    }
    temp=$(mktemp) || return 1
    printf '%s\n' "$key" > "$temp" || { rm -f -- "$temp"; return 1; }
    if ! ssh-keygen -l -f "$temp"; then rm -f -- "$temp"; log ERROR '公钥无效'; return 1; fi
    rm -f -- "$temp"
    as_user mkdir -p -- "$TARGET_HOME/.ssh" || return 1
    as_user chmod 700 -- "$TARGET_HOME/.ssh" || return 1
    if as_user test -e "$auth"; then
        as_user cp -a -- "$auth" "$auth.bak.$(date +%Y%m%d-%H%M%S).$$" || return 1
    fi
    as_user touch -- "$auth" || return 1
    as_user chmod 600 -- "$auth" || return 1
    if ! as_user grep -qxF -- "$key" "$auth"; then
        printf '\n%s\n' "$key" | as_user tee -a -- "$auth" >/dev/null || return 1
    fi
    as_root /usr/sbin/sshd -t || return 1
    as_root systemctl enable --now ssh.service || return 1
    log INFO "公钥已保存给 $TARGET_USER，已有 SSH 认证策略保持不变。"
    log INFO '请保留当前连接，用新连接验证公钥登录；成功后可执行 harden_ssh。'
    log INFO '自定义 AuthorizedKeysFile/Match/AllowUsers 等配置可能影响登录，请检查 sshd -T。'
}

harden_ssh() {
    local temp backup context effective addr host
    require_systemd || return 1
    [[ -x /usr/sbin/sshd ]] || { log ERROR '请先安装并配置 SSH'; return 1; }
    as_user test -s "$TARGET_HOME/.ssh/authorized_keys" || {
        log ERROR '目标用户没有 authorized_keys，请先执行 set_ssh'; return 1;
    }
    confirm "已在新连接中验证 $TARGET_USER 的公钥登录，并准备关闭全局密码登录（Match 条件需另查）？" || return 1
    temp=$(mktemp) || return 1
    backup="/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S).$$"
    as_root cp -a /etc/ssh/sshd_config "$backup" || { rm -f "$temp"; return 1; }
    # 放在文件首部，使全局值先于 Include；保留其他内容和 Match 段。
    {
        printf '# BEGIN somesh authentication\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n'
        if [[ $TARGET_USER == root ]]; then printf 'PermitRootLogin prohibit-password\n'; fi
        printf '# END somesh authentication\n'
        as_root sed '/^# BEGIN somesh authentication$/,/^# END somesh authentication$/d' /etc/ssh/sshd_config
    } > "$temp" || { rm -f "$temp"; return 1; }
    if ! as_root cp -- "$temp" /etc/ssh/sshd_config; then
        rm -f "$temp"; as_root cp -a "$backup" /etc/ssh/sshd_config; return 1
    fi
    rm -f "$temp"
    addr=${SSH_CONNECTION%% *}; addr=${addr:-127.0.0.1}
    host=$addr
    context="user=$TARGET_USER,addr=$addr,host=$host"
    if as_root /usr/sbin/sshd -t && effective=$(as_root /usr/sbin/sshd -T -C "$context") &&
       grep -qx 'pubkeyauthentication yes' <<< "$effective" &&
       grep -qx 'passwordauthentication no' <<< "$effective" &&
       grep -qx 'kbdinteractiveauthentication no' <<< "$effective"; then
        if as_root systemctl reload ssh.service; then
            log INFO "SSH 配置已生效；备份：$backup"
            log WARN '已验证当前用户/来源地址，其他 Match 条件需单独检查。请再次验证新连接。'
            return 0
        fi
    fi
    log ERROR 'SSH 校验或 reload 失败，正在恢复配置'
    as_root cp -a "$backup" /etc/ssh/sshd_config || return 1
    as_root systemctl reload ssh.service || log WARN '恢复后的 reload 失败，请检查 ssh.service'
    return 1
}

set_ntp() {
    local unit selected='' installed=''
    require_systemd || return 1
    [[ $TIMEZONE != /* && $TIMEZONE != *..* && -f /usr/share/zoneinfo/$TIMEZONE ]] || {
        log ERROR "无效时区：$TIMEZONE"; return 1;
    }
    # 优先沿用正在运行的提供者，其次沿用已安装的提供者。
    for unit in chrony.service ntpsec.service systemd-timesyncd.service; do
        if systemctl is-active --quiet "$unit"; then selected=$unit; break; fi
        if [[ -z $installed && $(systemctl show -p LoadState --value "$unit" 2>/dev/null) == loaded ]]; then
            installed=$unit
        fi
    done
    selected=${selected:-$installed}
    if [[ -z $selected ]]; then
        apt_install systemd-timesyncd || return 1
        selected=systemd-timesyncd.service
    fi
    as_root timedatectl set-timezone "$TIMEZONE" || return 1
    as_root systemctl enable --now "$selected" || return 1
    log INFO "时间同步服务：$selected；时区：$TIMEZONE（同步完成可能需要等待）"
    timedatectl status
}

set_update() {
    apt_update || return 1
    as_root apt-get --simulate dist-upgrade || return 1
    confirm '是否执行上述系统升级？' || return 1
    as_root apt-get dist-upgrade -y
}

set_clean() {
    apt_update || return 1
    as_root apt-get --simulate autoremove --purge || return 1
    if confirm '是否删除上述不再需要的软件包？'; then
        as_root apt-get autoremove --purge -y || return 1
    fi
    as_root apt-get clean || return 1
    log INFO '软件缓存已清理；没有调用远程清理脚本或手动删除内核。'
}

clean_log() {
    require_systemd || return 1
    as_root journalctl --rotate || return 1
    as_root journalctl --vacuum-time=14d || return 1
    log INFO '已清理超过 14 天的归档 journal；活动日志、登录记录及 shell 历史保留。'
}

app_docker() {
    local package
    require_systemd || return 1
    for package in docker-ce docker-ce-cli containerd.io podman-docker; do
        if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]]; then
            log ERROR "检测到 $package，请沿用现有安装源，不与 docker.io 混装"; return 1
        fi
    done
    apt_install docker.io || return 1
    as_root systemctl enable --now docker.service || return 1
    as_root docker version || return 1
    log INFO 'Docker 已安装（Debian 维护版）；未自动赋予普通用户 docker 组权限。'
}

# 独立子 shell 内处理临时文件与回滚，避免改变菜单的 umask/trap。
docker_tcp_tls() (
    umask 077
    local certdir=/etc/docker/tls/somesh drop=/etc/systemd/system/docker.service.d/90-somesh-tls.conf
    local stage='' candidate='' backup='' changed=0 had_drop=0 committed=0
    local bin current original san probe endpoint address dir kind=host
    local role key cert purpose public_cert public_key
    local daemon_args=() curl_args=()
    require_systemd || return 1
    bin=$(as_root sh -c 'command -v dockerd') || { log ERROR '请先安装 Docker（app_docker）'; return 1; }
    case "$bin" in /usr/bin/dockerd|/usr/sbin/dockerd) ;; *) log ERROR '仅支持标准 Docker systemd 安装'; return 1 ;; esac
    as_root systemctl is-active --quiet docker.service || { log ERROR '请先启动 docker.service'; return 1; }
    apt_install ca-certificates openssl python3 curl || return 1
    # 连接地址：显式参数优先，自动查询失败才手动输入。
    if [[ -z $DOCKER_TLS_HOST ]]; then
        log INFO '正在查询服务器公网 IPv4…'
        for endpoint in https://ipinfo.io/ip https://api.ipify.org; do
            address=$(curl -4 --silent --fail --noproxy '*' --proto '=https' \
                --connect-timeout 3 --max-time 5 --max-filesize 64 "$endpoint") || continue
            if python3 - "$address" <<'PY'
import ipaddress, sys
try:
    ip = ipaddress.IPv4Address(sys.argv[1])
    sys.exit(0 if ip.is_global and not ip.is_multicast else 1)
except ValueError:
    sys.exit(1)
PY
            then
                DOCKER_TLS_HOST=$address
                log INFO "检测到公网 IPv4：$address"
                log WARN '公网出口 IP 不保证 NAT 入站可达；内网或域名连接请指定 --docker-host。'
                break
            fi
        done
        [[ -n $DOCKER_TLS_HOST ]] || read_input '无法自动获取；请输入服务器 IPv4 或域名：' DOCKER_TLS_HOST || return 1
    fi
    # 校验地址并构造 SAN，拒绝把配置语法混入证书。
    san=$(python3 - "$DOCKER_TLS_HOST" "$DOCKER_TLS_BIND" <<'PY'
import ipaddress, re, sys
host, bind = sys.argv[1:]
try:
    ipaddress.IPv4Address(bind)
    try:
        ip = ipaddress.IPv4Address(host)
        if ip.is_unspecified or ip.is_multicast:
            raise ValueError('连接地址不能是通配或组播地址')
        san = 'IP:' + str(ip)
    except ipaddress.AddressValueError:
        if re.fullmatch(r'[0-9.]+', host) or len(host) > 253 or not all(
            re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label)
            for label in host.split('.')
        ):
            raise ValueError('请提供合法 IPv4 或 DNS 名称，不含协议、端口或路径')
        san = 'DNS:' + host
    print(san + ',IP:127.0.0.1')
except ValueError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(1)
PY
    ) || return 1
    # hosts/TLS 不能同时在 daemon.json 和 ExecStart 中定义。
    if as_root test -e /etc/docker/daemon.json; then
        as_root python3 - /etc/docker/daemon.json <<'PY' || return 1
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if not isinstance(data, dict):
    sys.exit('daemon.json 必须是 JSON 对象')
conflicts = set(data) & {'hosts', 'tls', 'tlsverify', 'tlscacert', 'tlscert', 'tlskey'}
if conflicts:
    sys.exit('daemon.json 中存在冲突项，请先手动整合：' + ', '.join(sorted(conflicts)))
PY
    fi
    current=$(as_root systemctl show docker.service -p ExecStart --value) || return 1
    if [[ $current =~ argv\[\]=([^\;]+) ]]; then
        current=${BASH_REMATCH[1]}; current=${current% }
    else log ERROR '无法识别 Docker ExecStart，未修改配置'; return 1; fi
    original="$bin -H fd:// --containerd=/run/containerd/containerd.sock"
    if as_root test -f "$drop"; then
        had_drop=1
        as_root grep -qxF '# Managed by somesh Docker TLS' "$drop" || {
            log ERROR '目标 drop-in 已存在且不是本脚本管理的文件'; return 1;
        }
        original=$(as_root sed -n 's/^ExecStart=\(.\+\)$/\1/p' "$drop") || return 1
    fi
    [[ $current == "$original" ]] || {
        log ERROR '检测到自定义 Docker 启动参数，请先手动整合；脚本不会覆盖它们。'; return 1;
    }
    log WARN "将监听 $DOCKER_TLS_BIND:2376，并重启 Docker，可能短暂影响容器。"
    log WARN '客户端私钥具有 Docker 管理权限；防火墙/安全组仅应向 DPanel 来源开放 2376。'
    confirm "确认以 tcp://$DOCKER_TLS_HOST:2376 配置 Docker 双向 TLS？" || return 1
    trap '
        rc=$?
        if ((changed && !committed)); then
            log ERROR "应用失败，恢复 Docker 原配置"
            if ((had_drop)); then
                as_root cp -a -- "$backup" "$drop" || log ERROR "恢复失败，请从 $backup 手动恢复"
            else
                as_root rm -f -- "$drop" || log ERROR "请手动删除 $drop"
            fi
            as_root systemctl daemon-reload && as_root systemctl restart docker.service || log ERROR "Docker 恢复启动失败，请检查 journalctl -u docker"
        fi
        [[ -z $candidate ]] || rm -f -- "$candidate"
        [[ -z $stage ]] || as_root rm -rf -- "$stage"
        # 已安装证书失败时也保留，便于诊断及重试；不会替换已有 CA。
        exit "$rc"
    ' EXIT
    # 首次生成，后续复用；两条路径汇合后执行同一组证书检查。
    dir=$certdir
    if ! as_root test -e "$certdir"; then
        as_root install -d -m 700 /etc/docker/tls || return 1
        stage=$(as_root mktemp -d /etc/docker/tls/.somesh.XXXXXXXX) || return 1
        dir=$stage
        # 在私有临时目录中签发证书，通过校验后再移入正式目录。
        as_root openssl genrsa -out "$dir/ca-key.pem" 3072 || return 1
        as_root openssl req -new -x509 -sha256 -days 3650 -key "$dir/ca-key.pem" \
            -subj '/CN=somesh Docker CA' -addext 'basicConstraints=critical,CA:TRUE' \
            -addext 'keyUsage=critical,keyCertSign,cRLSign' -out "$dir/ca.pem" || return 1
        for role in server client; do
            if [[ $role == server ]]; then
                key=server-key.pem; cert=server-cert.pem; purpose=serverAuth
            else
                key=key.pem; cert=cert.pem; purpose=clientAuth
            fi
            as_root openssl genrsa -out "$dir/$key" 3072 || return 1
            as_root openssl req -new -sha256 -key "$dir/$key" -subj "/CN=docker-$role" \
                -out "$dir/$role.csr" || return 1
            {
                printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=%s\n' "$purpose"
                if [[ $role == server ]]; then printf 'subjectAltName=%s\n' "$san"; fi
            } | as_root tee "$dir/$role.cnf" >/dev/null || return 1
            as_root openssl x509 -req -sha256 -days 365 -in "$dir/$role.csr" \
                -CA "$dir/ca.pem" -CAkey "$dir/ca-key.pem" -CAcreateserial \
                -extfile "$dir/$role.cnf" -out "$dir/$cert" || return 1
        done
        as_root chmod 600 "$dir/ca-key.pem" "$dir/server-key.pem" "$dir/key.pem" || return 1
        as_root rm -f -- "$dir/server.csr" "$dir/client.csr" "$dir/server.cnf" "$dir/client.cnf" || return 1
    fi
    [[ $DOCKER_TLS_HOST =~ ^[0-9.]+$ ]] && kind=ip
    as_root openssl verify -purpose sslserver -CAfile "$dir/ca.pem" "$dir/server-cert.pem" || return 1
    as_root openssl verify -purpose sslclient -CAfile "$dir/ca.pem" "$dir/cert.pem" || return 1
    as_root openssl x509 -in "$dir/server-cert.pem" "-check$kind" "$DOCKER_TLS_HOST" -noout || return 1
    for cert in ca.pem server-cert.pem cert.pem; do
        as_root openssl x509 -checkend 86400 -noout -in "$dir/$cert" || return 1
        case "$cert" in
            ca.pem) key=ca-key.pem ;;
            server-cert.pem) key=server-key.pem ;;
            cert.pem) key=key.pem ;;
        esac
        public_cert=$(as_root openssl x509 -in "$dir/$cert" -pubkey -noout) || return 1
        public_key=$(as_root openssl pkey -in "$dir/$key" -pubout) || return 1
        [[ $public_cert == "$public_key" ]] || { log ERROR "证书与私钥不匹配：$cert"; return 1; }
    done
    if [[ -n $stage ]]; then
        as_root mv -T -- "$stage" "$certdir" || return 1
        stage=''
    fi
    # 一份参数同时用于离线校验与 systemd，避免两处配置漂移。
    daemon_args=(-H fd:// -H "tcp://$DOCKER_TLS_BIND:2376"
        --containerd=/run/containerd/containerd.sock --tlsverify
        "--tlscacert=$certdir/ca.pem" "--tlscert=$certdir/server-cert.pem" "--tlskey=$certdir/server-key.pem")
    as_root "$bin" --validate "${daemon_args[@]}" || return 1
    candidate=$(mktemp) || return 1
    printf '# Managed by somesh Docker TLS\n[Service]\nExecStart=\nExecStart=%s %s\n' \
        "$bin" "${daemon_args[*]}" > "$candidate" || return 1
    as_root install -d -m 755 /etc/systemd/system/docker.service.d || return 1
    if ((had_drop)); then
        backup="$drop.bak.$(date +%Y%m%d-%H%M%S).$$"
        as_root cp -a -- "$drop" "$backup" || return 1
    fi
    changed=1
    as_root install -m 644 -- "$candidate" "$drop" || return 1
    as_root systemctl daemon-reload && as_root systemctl restart docker.service || return 1
    as_root systemctl is-active --quiet docker.service || return 1
    probe=$DOCKER_TLS_BIND
    [[ $probe == 0.0.0.0 ]] && probe=127.0.0.1
    # 同一地址分别检查带证书成功、无证书失败；不依赖公网回流。
    curl_args=(--silent --fail --noproxy '*' --connect-timeout 5 --max-time 15
        --connect-to "$DOCKER_TLS_HOST:2376:$probe:2376" --cacert "$certdir/ca.pem"
        "https://$DOCKER_TLS_HOST:2376/_ping")
    as_root curl "${curl_args[@]}" --show-error --cert "$certdir/cert.pem" --key "$certdir/key.pem" | grep -qx OK || return 1
    if as_root curl "${curl_args[@]}" >/dev/null 2>&1; then
        log ERROR '无客户端证书也能访问 Docker，已拒绝此配置'; return 1
    fi
    as_root tar -czf "$certdir/dpanel-client.tar.gz" -C "$certdir" ca.pem cert.pem key.pem || return 1
    as_root chmod 600 "$certdir/dpanel-client.tar.gz" || return 1
    committed=1
    log INFO "Docker TLS：tcp://$DOCKER_TLS_HOST:2376"
    log INFO "DPanel 上传 ca.pem、cert.pem、key.pem；导出包：$certdir/dpanel-client.tar.gz（仅 root 可读）"
    log INFO '客户端包不包含 CA 私钥或服务端私钥；证书有效期 365 天，重复执行复用已有证书。'
    return 0
)

app_zsh() {
    local rc="$TARGET_HOME/.zshrc"
    apt_install zsh zsh-autosuggestions zsh-syntax-highlighting || return 1
    if ! as_user test -e "$rc"; then
        as_user touch -- "$rc" || return 1
        as_user chmod 644 -- "$rc" || return 1
    else
        as_user cp -a -- "$rc" "$rc.bak.$(date +%Y%m%d-%H%M%S).$$" || return 1
    fi
    if ! as_user grep -qxF '# BEGIN somesh zsh' "$rc"; then
        as_user tee -a -- "$rc" >/dev/null <<'ZSH' || return 1

# BEGIN somesh zsh
export PATH="$HOME/.local/bin:$PATH"
autoload -Uz compinit && compinit
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
if (( $+commands[zoxide] )); then eval "$(zoxide init zsh)"; fi
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# END somesh zsh
ZSH
    fi
    as_root chsh -s /bin/zsh "$TARGET_USER" || return 1
    log INFO "已为 $TARGET_USER 配置 ZSH；重新登录生效。已有主题与 Oh My Zsh 配置保留。"
}

set_hostname() {
    local name=$HOSTNAME_VALUE
    require_systemd || return 1
    [[ -n $name ]] || read_input '请输入新主机名（单个 DNS 标签）：' name || return 1
    [[ ${#name} -le 63 && $name =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || {
        log ERROR '主机名需为 1–63 位字母/数字/连字符，不能以连字符开头或结尾'; return 1;
    }
    as_root hostnamectl set-hostname "$name" || return 1
    log INFO "主机名已设为 $name；若 /etc/hosts 或云平台配置包含旧名称，请同步更新。"
}

run_command() {
    is_command "$1" || { log ERROR "不支持的命令：$1"; return 1; }
    log INFO "开始：$1"
    if "$1"; then log INFO "完成：$1"; else log ERROR "失败：$1"; return 1; fi
}

main() {
    local command choice i
    local COMMANDS=()
    while (($#)); do
        case "$1" in
            -h|--help)
                cat <<'HELP'
用法：bash debian.sh [选项] [命令 ...]
无命令时显示数字菜单；保留旧版函数名作为命令。

选项：
  --user USER         SSH/ZSH/fd 配置的目标用户（默认 SUDO_USER 或当前用户）
  --timezone ZONE     时区，默认 Asia/Shanghai
  --ssh-key FILE      set_ssh 使用的单行 OpenSSH 公钥文件
  --hostname NAME     set_hostname 使用的主机名
  --docker-host HOST  DPanel 连接地址，写入证书 SAN；省略时自动查询公网 IPv4
  --docker-bind IPV4  Docker TLS 监听地址，默认 0.0.0.0，端口固定 2376
  -h, --help          显示帮助，不要求 root

命令：
  set_init / set_libs 安装常用工具；不自动升级整个系统
  set_swapfile       无活动 swap 时创建 1 GiB 或 2 GiB 交换文件
  set_ssh            验证并追加 SSH 公钥，不关闭密码登录
  harden_ssh         确认新连接已用公钥登录后，关闭密码及键盘交互认证
  set_ntp            配置时间同步，保留已有 chrony/ntpsec/timesyncd
  set_hostname       修改主机名
  set_update         刷新索引、预览变更，经确认后升级
  set_clean          清理软件缓存；预览后确认 autoremove
  clean_log          保留最近 14 天的 journal，不清空登录记录和历史
  app_docker         安装 Debian 仓库的 docker.io
  docker_tcp_tls     开启 Docker TCP 双向 TLS，生成 DPanel 客户端证书
  app_zsh            安装 ZSH 及仓库插件，保留已有 .zshrc
  install_sudo       可选安装 sudo，不修改用户组或 sudoers

root 可直接运行，无需 sudo。普通用户需已具有 sudo 权限；否则使用
su - 切换到 root，再执行 bash /脚本绝对路径/debian.sh --user 用户名。
需要服务的命令要求正在运行的 systemd；容器中仍可安装普通工具。
HELP
                return 0 ;;
            --user|--timezone|--ssh-key|--hostname|--docker-host|--docker-bind)
                if (($# < 2)) || [[ -z $2 || $2 == --* ]]; then
                    log ERROR "$1 缺少值"; return 1
                fi
                case "$1" in
                    --user) TARGET_USER=$2 ;;
                    --timezone) TIMEZONE=$2 ;;
                    --ssh-key) SSH_KEY_FILE=$2 ;;
                    --hostname) HOSTNAME_VALUE=$2 ;;
                    --docker-host) DOCKER_TLS_HOST=$2 ;;
                    --docker-bind) DOCKER_TLS_BIND=$2 ;;
                esac
                shift 2 ;;
            set_init) COMMANDS+=(set_libs); shift ;;
            *)
                is_command "$1" || { log ERROR "未知命令：$1"; return 1; }
                COMMANDS+=("$1"); shift ;;
        esac
    done
    [[ -r /etc/os-release ]] || { log ERROR '找不到 /etc/os-release'; return 1; }
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}:${VERSION_ID:-}" in
        debian:12|debian:13) log INFO "系统：Debian $VERSION_ID (${VERSION_CODENAME:-unknown})" ;;
        *) log ERROR '仅支持 Debian 12 和 Debian 13'; return 1 ;;
    esac
    has apt-get || { log ERROR '找不到 apt-get'; return 1; }
    if ((EUID != 0)); then
        if ! has sudo; then
            log ERROR '当前不是 root，且未安装 sudo。请先 su -，再以 root 运行本脚本。'
            return 1
        fi
        sudo -v || { log ERROR '无法取得 sudo 权限'; return 1; }
    fi
    local entry unused uid gid gecos shell
    TARGET_USER=${TARGET_USER:-${SUDO_USER:-$(id -un)}}
    entry=$(getent passwd "$TARGET_USER") || { log ERROR "用户不存在：$TARGET_USER"; return 1; }
    IFS=: read -r TARGET_USER unused uid gid gecos TARGET_HOME shell <<< "$entry"
    [[ $TARGET_HOME == /* && $TARGET_HOME != / && -d $TARGET_HOME ]] || {
        log ERROR '目标用户家目录不存在或不适合写入配置'; return 1;
    }
    log INFO "用户配置目标：$TARGET_USER ($TARGET_HOME)"
    if ((${#COMMANDS[@]})); then
        for command in "${COMMANDS[@]}"; do run_command "$command" || return 1; done
        return 0
    fi
    local actions=(set_libs set_swapfile set_ssh harden_ssh set_ntp set_hostname set_update set_clean clean_log app_docker app_zsh install_sudo docker_tcp_tls)
    local labels=('安装常用工具' '配置 swap' '添加 SSH 公钥' '关闭 SSH 密码登录' '配置时间同步' '修改主机名' '升级系统' '清理软件缓存及无用包' '清理旧 journal' '安装 Docker' '配置 ZSH' '安装 sudo（可选）' '开启 Docker TCP 双向 TLS')
    while true; do
        printf '\nDebian 管理工具 · 用户 %s\n' "$TARGET_USER"
        for i in "${!actions[@]}"; do printf '%2d) %s\n' "$((i+1))" "${labels[i]}"; done
        printf ' 0) 退出\n'
        read_input '请选择数字：' choice || return 1
        case "$choice" in
            0) return 0 ;;
            [1-9]|1[0-3]) run_command "${actions[choice-1]}" || log WARN '操作失败，可查看上方错误后重试' ;;
            *) log WARN '请输入菜单中的数字' ;;
        esac
    done
}

# 可被测试脚本 source；加载函数不会安装软件或修改系统。
if [[ -z ${BASH_SOURCE[0]:-} || ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
