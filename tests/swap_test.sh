#!/usr/bin/env bash
# 模拟内存、磁盘和所有特权调用，不写 /swapfile 或 /etc/fstab。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./debian.sh
awk() {
    case "${*: -1}" in
        /etc/fstab) return 1 ;;
        /proc/meminfo) printf '%s\n' "$MEM" ;;
        *) cat >/dev/null; printf '%s\n' "$FREE" ;;
    esac
}
stat() { printf 'ext2/ext3\n'; }
df() { printf 'unused\n'; }
as_root() {
    case "$1" in
        swapon) [[ ${2:-} != --show ]] || printf '%s' "${ACTIVE:-}" ;;
        test) return 1 ;;
        dd) local arg; for arg in "$@"; do [[ $arg != count=* ]] || CREATED=${arg#count=}; done ;;
        tee) cat >/dev/null ;;
        bash|mkswap|rm|cp) : ;;
        *) return 99 ;;
    esac
}
for scenario in '512 100000 1024' '1024 100000 2048' '2048 100000 4096' '4096 100000 4096' '8192 100000 8192' '16384 100000 8192' '65536 100000 16384' '3073 100000 3328' '128 100000 512' '8192 3072 2048'; do
    read -r MEM FREE EXPECTED <<< "$scenario"
    CREATED=''
    set_swapfile
    [[ $CREATED == "$EXPECTED" ]] || { echo "FAIL $scenario -> $CREATED"; exit 1; }
done
MEM=8192 FREE=1400 CREATED=''
if set_swapfile; then echo 'FAIL accepted insufficient disk'; exit 1; fi
[[ -z $CREATED ]]
MEM=0 FREE=100000
if set_swapfile; then echo 'FAIL accepted invalid memory'; exit 1; fi
ACTIVE='existing swap'
set_swapfile
[[ -z $CREATED ]]
printf 'PASS 13 swap scenarios: memory tiers, alignment, cap, disk clamp, failures and existing swap\n'
