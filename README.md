# 国内 VPS 海外网络一键配置

目标只有一个：**国内 / 私网资源直连，海外和未知目标通过海外 VLESS 节点访问。**

普通使用者不需要理解 Xray、geoip、geosite、SOCKS 或路由规则。

## 仓库结构

```text
setup-xray-vless.sh   # 安装 / 重新配置入口
xray-vless-manager    # 节点管理、移除、卸载、归还清理
xray-proxy-test       # 代理健康检查
README.md
```

安装时后两个工具会自动复制到 `/usr/local/bin/`，所以安装完成后可以直接当系统命令使用。

## 安装

建议完整 clone 本分支后执行：

```bash
sudo bash setup-xray-vless.sh
```

脚本会要求粘贴 VLESS 分享链接，**输入是隐藏的**。

为了避免凭据进入 shell history，当前版本故意禁止：

```bash
sudo bash setup-xray-vless.sh 'vless://...'
```

也就是说，VLESS 链接不要再作为命令行参数传入。

安装完成后脚本会自动检查 Xray、Google、GitHub 和代理出口 IP。

## 日常命令

```bash
xray-vless-manager status       # 看当前状态
xray-vless-manager test         # 检查代理链路
xray-proxy-test                 # 同样的健康检查，可直接调用
proxy_on                        # 当前 shell 使用本机代理
proxy_off                       # 当前 shell 取消代理
```

如果刚安装完当前 shell 还找不到 `proxy_on`：

```bash
source /etc/profile.d/xray-proxy.sh
```

## 更换节点

```bash
sudo xray-vless-manager set-node
```

然后隐藏输入新的 VLESS 链接即可。

它会调用本机保存的安装入口重新生成配置、校验、重启并测试，不需要手工编辑 JSON。

当前版本不会长期保存旧节点配置备份，并会清理早期版本留下的 `config.json.bak.*`。

## 暂时移除节点

```bash
sudo xray-vless-manager remove-node
```

会停止 Xray、删除当前节点配置和旧配置备份，并撤掉 Docker daemon 的 Xray 代理配置；Xray 程序和管理工具仍保留。

以后恢复直接执行：

```bash
sudo xray-vless-manager set-node
```

如果当前 shell 之前运行过 `proxy_on`，再运行一次：

```bash
proxy_off
```

## 归还 / 转让服务器

推荐在**当前 Bash shell**中执行：

```bash
xray_return_cleanup
```

它会先：

1. 关闭当前 shell 的代理环境变量。
2. 只从当前 Bash 内存 history 中删除包含 `vless://` 的命令，不清空其他正常历史。
3. 把清理后的 history 写回磁盘。
4. 执行完整卸载。
5. 扫描常见用户的 `.bash_history` / `.zsh_history` / `.sh_history` / `.ash_history`，删除包含 `vless://` 的历史行。

完整卸载会删除：

- 当前 VLESS 节点配置及旧备份
- Xray systemd 服务
- Xray 二进制和地域数据
- `proxy_on / proxy_off`
- `xray-proxy-test`
- `xray-vless-manager`
- Docker daemon 的 Xray 代理配置
- 本机保存的安装脚本副本

如果不方便调用 shell function，也可以：

```bash
sudo xray-vless-manager uninstall --purge-history
```

但它只能清理已经落盘的历史文件；父 shell 当前尚未写盘的内存 history 不能由子进程直接修改，因此归还机器时优先使用 `xray_return_cleanup`。

如果只想单独扫描并删除落盘 history 里的 VLESS 链接：

```bash
sudo xray-vless-manager purge-history
```

### 一个重要边界

历史清理针对常见 shell history 和本项目的配置文件。

如果过去曾把 VLESS 链接直接放进命令行参数，系统级 sudo/audit/journal、终端录屏、第三方运维平台日志等位置理论上仍可能留痕。本脚本不会为了清一条凭据而粗暴删除整台服务器的系统审计日志。

因此最安全的长期规则是：**从现在开始只使用隐藏输入；服务器退役时同时在节点服务端撤销/更换旧凭据。**

文件系统或 SSD 的底层数据恢复属于云厂商和存储层问题，普通卸载脚本也无法承诺物理层不可恢复。

## 是否需要维护网站白名单？

不需要。

```text
国内 / 私网资源  -> DIRECT
海外资源          -> VLESS
未知的新目标      -> VLESS
```

普通使用者不用手工维护 geoip / geosite 规则文件。

## Docker

如果安装时服务器已经有 Docker，脚本会自动给 Docker daemon 配置本机 HTTP 代理，主要用于镜像拉取和 Registry 访问。

`remove-node` 和 `uninstall` 都会自动撤掉这份 Docker 配置，避免留下失效代理。

容器内部是否需要代理，由具体应用部署脚本处理；后续例如 Hindsight 的部署不要求使用者自己研究 Docker 网络。

## 不要用 ping 判断代理

```bash
ping google.com
```

使用的是 ICMP，不会进入当前 HTTP / SOCKS 代理。

判断是否正常直接运行：

```bash
xray-vless-manager test
```

## 当前已验证

在腾讯云国内 VPS 上已经实际验证：Xray 正常启动、GitHub 和 Google 可以经海外节点访问、Gitee 国内镜像可高速获取 Xray 安装包、本地 SOCKS5 / HTTP 链路正常。

Xray 二进制优先来自：

```text
https://gitee.com/skyhigh13/xray_bin.git
```

当前默认版本：`v26.3.27`。

支持常见 VPS 架构：`x86_64 / amd64`、`arm64 / aarch64`、`armv7`。

---

# 高级说明 / 排障

普通使用者可以不看这一部分。

## 本地端口

```text
SOCKS5  socks5h://127.0.0.1:10808
HTTP    http://127.0.0.1:10809
```

只监听 `127.0.0.1`，不会直接暴露到公网。

进入 Xray 后：

```text
私网地址       -> DIRECT
中国大陆 IP    -> DIRECT
中国大陆域名   -> DIRECT
其他目标       -> VLESS
```

这不是透明代理。只有显式使用本机代理的程序才会进入 Xray；SSH、ICMP 等不会被劫持。

## 手动排障

```bash
systemctl status xray --no-pager
journalctl -u xray -n 100 --no-pager
curl -I --socks5-hostname 127.0.0.1:10808 https://www.google.com
curl -I -x http://127.0.0.1:10809 https://github.com
```

## 服务器上的主要文件

```text
/usr/local/bin/xray
/usr/local/bin/xray-proxy-test
/usr/local/bin/xray-vless-manager
/usr/local/etc/xray/config.json
/usr/local/share/xray/
/usr/local/libexec/xray-vless/setup-xray-vless.sh
/etc/profile.d/xray-proxy.sh
/etc/systemd/system/xray.service
```

Docker 已安装时还有：

```text
/etc/systemd/system/docker.service.d/xray-proxy.conf
```

## Xray 下载策略

```text
Gitee 二进制镜像
    -> 失败后 SourceForge
    -> 失败后 GitHub 加速源
    -> 最后官方 GitHub
```

Gitee Raw ZIP 匿名下载曾返回 HTTP 403，因此大文件使用 Git clone 获取镜像。在已测试的腾讯云 VPS 上，Gitee Git 通道曾达到约 11 MiB/s。

工具脚本优先从当前仓库目录直接安装；如果只单独运行 `setup-xray-vless.sh`，安装器会尝试获取缺失的小型工具文件。国内网络无法获取时，应使用完整仓库目录执行安装。

临时指定 Xray 版本：

```bash
XRAY_VERSION=v26.3.27 sudo -E bash setup-xray-vless.sh
```
