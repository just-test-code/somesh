# Debian 服务器管理脚本

支持 Debian 12（bookworm）和 Debian 13（trixie），需要 Bash。

脚本按功能组织：每个菜单功能集中在一个函数中；只有日志、权限、输入确认、
APT 和命令分发等多处复用的逻辑保留为公共函数。`set_init` 是 `set_libs` 的命令别名。

## 权限与目标用户

root 可以直接运行，**不需要安装 sudo**：

```bash
bash /path/to/debian.sh
bash /path/to/debian.sh set_init
```

普通用户已具有 sudo 权限时，可以直接运行脚本，系统操作会自动使用 sudo。
普通用户没有 sudo 时，先使用 `su -` 取得 root 会话，再执行：

```bash
bash /path/to/debian.sh --user alice set_init app_zsh
```

`alice` 必须是已存在且有家目录的用户。`--user` 只指定用户配置的归属，
不会创建用户或授予管理员权限。默认使用 `SUDO_USER`，否则使用当前用户。
通过 `su -` 启动时不能可靠推断原用户，因此需要显式指定 `--user`。

sudo 已放入“安装常用工具”，默认勾选；脚本不会修改 sudoers 或用户组。
旧的单独安装命令仍可由 root 使用：

```bash
bash /path/to/debian.sh install_sudo
```

## 常见用法

```bash
bash debian.sh --help
bash debian.sh --timezone Asia/Singapore set_ntp
bash debian.sh --hostname my-server set_hostname
bash debian.sh --user alice --ssh-key /path/to/id_ed25519.pub set_ssh
```

命令可以批量执行；任一步失败即停止后续命令并返回非零状态。
不带命令时使用方向键菜单：上下键移动、回车执行，也支持数字后回车和 q 退出。
菜单按基础安装、Docker、SSH、系统配置、维护操作分组排序，相关操作相邻。
“常用脚本”父菜单包含“NQ脚本”，执行命令为：

```bash
bash <(curl -sL https://run.NodeQuality.com)
```

脚本以当前执行用户身份运行，交互输入连接到终端；完成后按任意键返回子菜单。
子菜单支持上下键、数字选择及 q/“返回上级菜单”，返回后保留主菜单选中位置。
日志在终端显示颜色（信息青色、成功绿色、警告黄色、错误红色）；
重定向输出或设置 `NO_COLOR=1` 时日志为纯文本。
需要输入时从 `/dev/tty` 读取；无终端则明确失败，不会把 EOF 当成菜单确认。
虽然支持 `curl | bash` 的终端输入，建议先保存脚本再运行，便于审阅和复用参数。

“安装常用工具”默认全部勾选，并显示每个软件包的中文用途说明：上下键移动，
空格切换，a 全选、n 清空、回车安装、q 取消。仅安装选中的包及其 APT 依赖，
只有选中 fd/bat 才创建对应短命令链接。非交互安装全部可用工具可使用：

```bash
bash debian.sh --all-tools set_libs
```

## Debian 12/13 兼容策略

| 项目 | 策略 |
| --- | --- |
| 系统检测 | 读取 `/etc/os-release`，仅接受 Debian 12/13 |
| 权限 | root 直接执行；普通用户使用 sudo；缺少权限时给出 `su -` 指引 |
| 软件安装 | 使用 apt-get；一次运行复用成功的索引刷新；失败停止 |
| zoxide | 使用两个发行版各自的软件仓库版本，不执行在线安装脚本 |
| eza | 检查实际候选包；Debian 13 标准源可安装，Debian 12 缺包时提示并跳过；不添加跨版本源 |
| fd/bat | 安装 fd-find/bat，给目标用户建立 fd/bat 链接；已有文件保留 |
| NTP | 保留已运行或已安装的 chrony、ntpsec、systemd-timesyncd；都不存在才安装 timesyncd |
| SSH | 使用 ssh.service 和 sshd -t；不再写入 Protocol/RSAAuthentication 旧配置项 |
| Docker | 使用 Debian 的 docker.io；检测到 Docker CE 等冲突安装时停止 |
| ZSH | 使用 Debian 的 zsh-autosuggestions、zsh-syntax-highlighting；配置目标用户的 shell |
| 服务环境 | 检查 systemd 正在运行；普通容器仅支持不依赖服务的功能 |

软件源应与系统发行版一致。脚本不会自动切换 APT 源或把 Debian 13 软件包装进 Debian 12。
不同版本的工具功能可能不同；本脚本不保证仓库版与上游最新版完全一致。

## SSH 密钥登录流程

1. 选择“配置 SSH 密钥登录”或执行 `set_ssh`，校验并追加公钥，保留其他密钥。
2. 添加成功后，脚本会追问是否关闭密码登录。先保留原连接，在新连接中验证公钥登录，再回答 y。
3. 回答 n、直接回车或无法读取确认时，只保留已添加的公钥，不改变密码登录策略。菜单不再提供独立的关闭密码登录项。

确认关闭后，脚本会备份 sshd_config，在开头写入可重复更新的管理块，执行语法与
目标用户/来源地址的有效配置检查，再 reload ssh.service。失败会尝试恢复备份。
全局配置不能覆盖所有 Match 情形，其他来源地址、Host 匹配和用户条件需要另行核查。
自定义 AuthorizedKeysFile、AllowUsers、AuthenticationMethods 等也可能影响公钥登录。
`--user root` 关闭密码登录时使用 `PermitRootLogin prohibit-password`。

## 与旧版的行为变化

- 初始化只安装常用工具；升级需单独运行 `set_update` 并确认预览结果。
- SSH 添加密钥后追问是否关闭密码认证，默认保持原策略；不会覆盖其他公钥。
- 不再自动安装 Oh My Zsh 和远程主题；已有 .zshrc 会备份并保留，追加一次管理块。
- 不再运行远程 server_cleanup.sh，也不执行 Docker prune 或模糊匹配删除内核。
- 系统清理预览 apt autoremove，确认后删除软件包并清理下载缓存。
- 日志清理仅移除超过 14 天的归档 journal，不清空活动日志、登录记录或 shell 历史。
- swap 支持普通 ext4/XFS 场景；已有活动 swap 时跳过，不覆盖已有 /swapfile。
  按 `/proc/meminfo` 的实际内存计算：不超过 2 GiB 取 2 倍，2–8 GiB 取等量，
  超过 8 GiB 取一半；向上对齐 256 MiB，最低 512 MiB、最高 16 GiB。
  同时预留至少 1 GiB 或当前磁盘可用空间的 10%（取较大值），空间不足时缩小 swap，
  连最低大小都无法满足则停止。这是普通服务器策略，不包含休眠所需空间。
- 修改主机名使用 hostnamectl；定制的 /etc/hosts 和云平台主机名设置需要同步维护。

## 验证

```bash
bash -n debian.sh
bash tests/debian_test.sh
bash tests/docker_host_test.sh
bash tests/docker_tls_test.sh
bash tests/swap_test.sh
bash tests/ssh_test.sh
python3 tests/menu_test.py
```

回归测试通过 mock 检查权限分支、参数白名单、APT 失败传播、批量失败中断、
可选包缺失、链接保护、时间服务选择、主机名和公钥输入校验，不会安装软件或修改系统。
基础测试在 Linux root/普通用户环境运行；TLS 测试在 Git Bash 中生成真实证书并验证
本地握手，Docker/systemd 和系统路径使用沙箱模拟，覆盖证书复用与配置回滚。
Debian 12/13 容器集成验证因
当前环境无法访问镜像仓库而未完成；SSH reload、APT 安装和 swap 仍需在一次性
Debian 12/13 虚拟机上进行实际验证。ShellCheck 尚未运行。

## Docker TCP 双向 TLS（DPanel）

根据 [DPanel TCP TLS 文档](https://dpanel.cc/manual/system-env-tcp) 和
[Docker TLS 文档](https://docs.docker.com/engine/security/protect-access/) 实现。
先安装并启动 Docker，然后选择菜单“开启 Docker TCP 双向 TLS”，或指定连接地址：

```bash
# 自动查询服务器公网 IPv4，在启用前显示地址并确认。
bash debian.sh docker_tcp_tls

# 域名需要指向这台 Docker 主机，也可直接填写服务器 IPv4。
bash debian.sh --docker-host docker.example.com docker_tcp_tls

# 可选：仅监听主机的某个内网 IPv4；默认监听 0.0.0.0。
bash debian.sh --docker-host 10.0.0.10 --docker-bind 10.0.0.10 docker_tcp_tls

# 首次签发时选择五年；不传此选项时会询问 1 / 5 / 10 年，回车默认一年。
bash debian.sh --docker-years 5 docker_tcp_tls
```

省略 `--docker-host` 时，依次通过 HTTPS 查询 ipinfo.io/ip 和 api.ipify.org，
每个服务最多等待 5 秒；绕过环境代理，仅接受合法公网 IPv4。查询失败时改为手动输入，
无交互终端则停止。显式指定地址时不进行公网查询。
自动查询得到的是服务器的公网出口 IP，NAT/云网关场景下不保证入站可达；
需要保证该地址的 TCP 2376 可到达这台主机。内网连接或域名连接应显式指定地址。
如果公网 IP 已改变，已有证书不能自动沿用新地址，需要规划证书轮换。

该操作会预告并确认 Docker 重启，可能短暂影响现有容器。需要正在运行的
系统级 docker.service，支持标准 Debian docker.io / Docker CE 的 systemd
启动参数；自定义 ExecStart 或 daemon.json 中已有 hosts/TLS 配置时停止，
避免丢失原有参数或制造重复配置。IPv6 和多域名 SAN 暂不支持。

- 监听端口为 **2376**，启用 `--tlsverify`，同时保留 `-H fd://` 的本地 socket。
- 使用 `/etc/systemd/system/docker.service.d/90-somesh-tls.conf`，不修改发行版 unit。
- 生成独立 CA、服务端证书和客户端证书；服务端 SAN 包含连接地址与 127.0.0.1。
- 服务端和客户端证书可选 1 / 5 / 10 年（按每年 365 天计算）。
  CA 至少有效 10 年，并至少比新签发的客户端/服务端证书多一年。
- 证书目录 `/etc/docker/tls/somesh` 为私有目录，私钥权限为 0600。
- 重复执行会验证并复用证书；地址改变、证书损坏或将在 24 小时内过期时停止，
  不自动替换 CA，避免现有客户端突然失去访问权限。到期前需要规划证书轮换。
  已有证书不会因重复执行而延长到期时间；显式选择不同年限时会停止并提示重新签发。
- 修改前执行 dockerd 配置校验；重启后检查带证书访问成功、无证书访问失败。
  应用失败会恢复原 drop-in 并尝试重启；备份文件和已生成证书保留供诊断。

在 DPanel 的多服务端设置中填写 `tcp://docker.example.com:2376`，启用 TLS，
上传这三个文件：

| DPanel 证书 | 服务器路径 |
| --- | --- |
| CA | `/etc/docker/tls/somesh/ca.pem` |
| 客户端证书 | `/etc/docker/tls/somesh/cert.pem` |
| 客户端私钥 | `/etc/docker/tls/somesh/key.pem` |

默认导出到**执行命令时的当前工作目录**，文件名为 `dpanel-client.tar.gz`，
不是固定放在证书目录或脚本文件所在目录。例如在 `/root/setup` 中执行
`bash /opt/scripts/debian.sh docker_tcp_tls`，导出包就在 `/root/setup/dpanel-client.tar.gz`。
包内只包含上述三个文件，权限为 0600，所有者为实际执行脚本的用户；
再次成功运行时原子替换同名导出包。
通过可信的 SSH/SFTP 通道取出；**不要上传 ca-key.pem 或 server-key.pem**。
持有客户端私钥即可管理 Docker，通常等同于拥有宿主机 root 权限。
脚本不修改防火墙或云安全组；请仅允许 DPanel 来源地址访问 TCP 2376。

Docker CLI 验证示例（在解压客户端包的目录执行）：

```bash
docker --tlsverify --tlscacert=ca.pem --tlscert=cert.pem --tlskey=key.pem \
  -H tcp://docker.example.com:2376 version
```

TLS 测试：`bash tests/docker_tls_test.sh`（需要 Python 3 和 OpenSSL）。
测试实际生成证书并建立本地 TLS 连接，验证正常客户端、缺少客户端证书、错误域名
以及私钥不匹配的情况。Windows 下不检查 POSIX 文件权限。
实际 Docker/systemd 重启与故障恢复仍需要在 Debian 12/13 测试机验证。
