"""真实 PTY 输入测试；APT/服务操作全部替换为记录输出。Linux/Python 3。"""
import os, pty, re, select, signal, time

SETUP = r'''
source ./debian.sh
function . { ID=debian; VERSION_ID=12; VERSION_CODENAME=test; }
getent() { printf 'demo:x:1000:1000::/tmp:/bin/bash\n'; }
has() { return 0; }
sudo() { return 0; }
apt_update() { :; }
apt_install() { printf 'PACKAGES:%s\n' "$*"; }
apt-cache() { printf '  Candidate: 1.0\n'; }
as_user() { :; }
app_docker() { log INFO 'ACTION_DOCKER'; }
docker_tcp_tls() { log INFO 'ACTION_TLS'; }
set_clean() { log INFO 'ACTION_CLEAN'; }
'''

class Terminal:
    def __init__(self, command, no_color=False):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ['TERM'] = 'xterm-256color'
            if no_color: os.environ['NO_COLOR'] = '1'
            os.execlp('bash', 'bash', '-c', SETUP + '\n' + command)
        self.buf = b''
    def send(self, text): os.write(self.fd, text.encode())
    def expect(self, text, timeout=5):
        target = text.encode()
        end = time.monotonic() + timeout
        while target not in self.buf:
            assert time.monotonic() < end, (text, self.buf.decode(errors='replace')[-1500:])
            if select.select([self.fd], [], [], .1)[0]:
                self.buf += os.read(self.fd, 65536)
        pos = self.buf.index(target) + len(target)
        found, self.buf = self.buf[:pos], self.buf[pos:]
        return found
    def close(self):
        try: os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        os.waitpid(self.pid, 0)
        os.close(self.fd)

# 主菜单进入工具选择，取消 sudo 和 curl，只安装其余选项，再操作相邻 Docker 菜单。
t = Terminal('main')
try:
    first = t.expect('数字输入：')
    assert b'\x1b[36m[INFO]' in first
    t.send('\n')
    tools = t.expect('源可能无此包）')
    assert tools.count(b'[x]') == 17
    assert '执行管理员命令'.encode() in tools
    t.send(' ')
    t.expect('源可能无此包）')
    t.send('\x1b[B'); t.expect('源可能无此包）')
    t.send('\x1b[B'); t.expect('源可能无此包）')
    t.send(' '); t.expect('源可能无此包）')
    t.send('\n')
    installed = t.expect('按任意键返回菜单')
    packages = re.search(rb'PACKAGES:([^\r\n]+)', installed).group(1).split()
    assert b'sudo' not in packages and b'curl' not in packages
    assert len(packages) == 15
    t.send(' '); t.expect('数字输入：')
    t.send('\x1b[B'); t.expect('数字输入：')
    t.send('\n'); t.expect('ACTION_DOCKER'); t.expect('按任意键返回菜单')
    t.send(' '); t.expect('数字输入：')
    t.send('\x1bOB'); t.expect('数字输入：')
    t.send('\n'); t.expect('ACTION_TLS'); t.expect('按任意键返回菜单')
    t.send(' '); t.expect('数字输入：')
    # 单独 ESC 超时后仍可输入，两位数字必须选择清理而不是误退出。
    t.send('\x1b'); time.sleep(.3)
    t.send('10\n'); t.expect('ACTION_CLEAN'); t.expect('按任意键返回菜单')
finally: t.close()
print('PASS PTY: arrows/alternate arrows, space selection, numeric 10, ESC timeout, colored logs')

for keys, expected_count in [('n\n', 0), ('na\n', 17), ('n \n', 1), ('q', 0)]:
    t = Terminal("set_libs; printf '\\nTEST_DONE\\n'")
    try:
        t.expect('源可能无此包）')
        t.send(keys)
        output = t.expect('TEST_DONE')
        found = re.search(rb'PACKAGES:([^\r\n]+)', output)
        assert (len(found.group(1).split()) if found else 0) == expected_count
    finally: t.close()
print('PASS PTY: empty/all/single selection and cancellation')

t = Terminal("log ERROR 'COLOR_TEST'; printf 'TEST_DONE\\n'", no_color=True)
try:
    assert b'\x1b[' not in t.expect('TEST_DONE')
finally: t.close()
print('PASS NO_COLOR')

# 远程脚本仅返回本地测试内容，验证实际进程替换执行与交互终端传递。
t = Terminal(r"""
curl() {
    [[ "$*" == '-sL https://run.NodeQuality.com' ]] || return 99
    printf '%s\n' 'printf "NQ_TEST_PROMPT\n"; read -r answer; printf "NQ_TEST_RESULT:%s\n" "$answer"'
}
main
""")
try:
    t.expect('数字输入：')
    t.send('12\n')
    t.expect('返回上级菜单'); t.expect('数字输入：')
    t.send('\n'); t.expect('NQ_TEST_PROMPT')
    t.send('hello\n'); t.expect('NQ_TEST_RESULT:hello')
    t.expect('按任意键返回菜单'); t.send(' ')
    t.expect('返回上级菜单'); t.expect('数字输入：')
    t.send('q'); t.expect('Debian 管理工具'); t.expect('数字输入：')
    # 返回主菜单后仍选中“常用脚本”；下箭头选择子菜单的返回项。
    t.send('\n'); t.expect('返回上级菜单'); t.expect('数字输入：')
    t.send('\x1b[B'); t.expect('数字输入：')
    t.send('\n'); t.expect('Debian 管理工具')
finally: t.close()
print('PASS NQ submenu: command, child TTY input, q/back navigation and preserved selection')
