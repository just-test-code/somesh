#!/usr/bin/env bash
# 调用完整 TLS 功能；真实生成证书，系统管理与网络调用限定在临时沙箱。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./debian.sh
source ./tests/docker_fixture.sh
fixture_setup
umask 077
docker_tcp_tls
work="$TLS_WORK/etc/docker/tls/somesh"
drop="$TLS_WORK/etc/systemd/system/docker.service.d/90-somesh-tls.conf"
[[ -f $TLS_WORK/dpanel-client.tar.gz && -f $drop && ! -e $work/dpanel-client.tar.gz ]]
[[ $(tar -tzf "$TLS_WORK/dpanel-client.tar.gz" | sort) == $(printf 'ca.pem\ncert.pem\nkey.pem') ]]
grep -qF -- '--tlsverify' "$drop"
grep -qF -- '-H fd://' "$drop"
validated=$(cat "$TLS_WORK/validated")
expected="/usr/bin/dockerd ${validated#--validate }"
[[ ${TEST_DOCKER_LEGACY:-0} != 1 ]] || expected+=' $DOCKER_OPTS'
[[ $(sed -n 's/^ExecStart=\(.\+\)$/\1/p' "$drop") == "$expected" ]]
checksum=$(sha256sum "$work/ca.pem" "$work/server-cert.pem" "$work/cert.pem")
docker_tcp_tls
[[ $(sha256sum "$work/ca.pem" "$work/server-cert.pem" "$work/cert.pem") == "$checksum" ]]
printf 'PASS certificate reuse, client export and matching validation/service arguments\n'
python3 - "$work" "$DOCKER_TLS_YEARS" <<'PY'
import pathlib, socket, ssl, sys, threading
p = pathlib.Path(sys.argv[1])
years = int(sys.argv[2])
dates = {}
for name in ['ca.pem', 'server-cert.pem', 'cert.pem']:
    decoded = ssl._ssl._test_decode_cert(str(p / name))
    start = ssl.cert_time_to_seconds(decoded['notBefore'])
    end = ssl.cert_time_to_seconds(decoded['notAfter'])
    dates[name] = end
    if name != 'ca.pem':
        assert end - start == years * 365 * 86400, (name, end - start)
assert dates['ca.pem'] > max(dates['server-cert.pem'], dates['cert.pem'])
print(f'PASS actual {years}-year certificate dates and longer CA validity')
server = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server.load_cert_chain(p / 'server-cert.pem', p / 'server-key.pem')
server.load_verify_locations(p / 'ca.pem')
server.verify_mode = ssl.CERT_REQUIRED
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen()
listener.settimeout(5)
port = listener.getsockname()[1]
results = []
def serve():
    for _ in range(3):
        raw, _ = listener.accept()
        raw.settimeout(5)
        try:
            with server.wrap_socket(raw, server_side=True) as tls:
                tls.sendall(b'OK')
            results.append(True)
        except OSError:
            raw.close()
            results.append(False)
t = threading.Thread(target=serve)
t.start()
for with_cert, name, expected in [(True, 'docker.example.com', True),
                                  (False, 'docker.example.com', False),
                                  (True, 'wrong.example.com', False)]:
    client = ssl.create_default_context(cafile=str(p / 'ca.pem'))
    if with_cert:
        client.load_cert_chain(p / 'cert.pem', p / 'key.pem')
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=5) as raw:
            with client.wrap_socket(raw, server_hostname=name) as tls:
                ok = tls.recv(2) == b'OK'
    except OSError:
        ok = False
    assert ok == expected, (with_cert, name, ok)
t.join(timeout=10)
listener.close()
assert not t.is_alive() and results == [True, False, False], results
if sys.platform != 'win32':
    for name in ['ca-key.pem', 'server-key.pem', 'key.pem']:
        assert (p / name).stat().st_mode & 0o777 == 0o600
    assert pathlib.Path('dpanel-client.tar.gz').stat().st_mode & 0o777 == 0o600
print('PASS actual mTLS: valid client accepted; no client certificate and wrong hostname rejected')
PY

# 重启失败时恢复已有配置，并再次启动；已生成的证书应保持不变。
cp "$drop" "$TLS_WORK/original.conf"
FAIL_RESTART=1
DOCKER_TLS_BIND=0.0.0.0
if docker_tcp_tls; then echo 'FAIL restart failure not propagated'; exit 1; fi
cmp "$drop" "$TLS_WORK/original.conf"
[[ $(tail -n 2 "$TLS_WORK/systemctl") == $(printf 'daemon-reload\nrestart docker.service') ]]
FAIL_RESTART=0
ALLOW_ANONYMOUS=1
if docker_tcp_tls; then echo 'FAIL anonymous client accepted'; exit 1; fi
cmp "$drop" "$TLS_WORK/original.conf"
ALLOW_ANONYMOUS=0
# 首次配置失败应删除本次 drop-in；复用之前生成的证书以避免重复签发。
rm "$drop" "$TLS_WORK/restart-failed"
FAIL_RESTART=1
if docker_tcp_tls; then echo 'FAIL new drop-in failure not propagated'; exit 1; fi
[[ ! -e $drop ]]
FAIL_RESTART=0
DOCKER_TLS_HOST=wrong.example.com
if docker_tcp_tls; then echo 'FAIL wrong certificate hostname accepted'; exit 1; fi
[[ ! -e $drop ]]
DOCKER_TLS_HOST=docker.example.com
cp "$work/server-key.pem" "$work/key.pem"
if docker_tcp_tls; then echo 'FAIL mismatched client key accepted'; exit 1; fi
[[ ! -e $drop ]]
printf 'PASS restart/anonymous rollback, new drop-in removal, hostname and key mismatch rejection\n'
