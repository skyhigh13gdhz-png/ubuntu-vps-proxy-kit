# 国内 VPS 海外网络一键配置

这个分支的目标很简单：**让国内 VPS 在需要访问海外服务时通过海外 VLESS 节点，同时国内资源保持直连。**

普通使用者不需要理解 Xray、geoip、geosite、SOCKS、路由规则这些概念。脚本会自动处理。

## 安装

```bash
sudo bash setup-xray-vless.sh
```

然后按照提示粘贴 VLESS 分享链接。输入过程隐藏，不会直接显示在终端里。

安装完成后看到：

```text
SUCCESS: Xray VLESS path, GitHub and Google access are working.
```

说明链路正常。

## 日常只需要记这些命令

查看当前状态：

```bash
xray-vless-manager status
```

检查代理链路：

```bash
xray-vless-manager test
```

旧命令 `xray-proxy-test` 也仍然可以直接使用。

当前终端需要使用代理：

```bash
proxy_on
```

关闭当前终端代理：

```bash
proxy_off
```

如果刚安装完当前终端还找不到 `proxy_on`：

```bash
source /etc/profile.d/xray-proxy.sh
```

## 更换 VLESS 节点

不需要重新研究配置文件，也不要手工改 JSON。

直接执行：

```bash
sudo xray-vless-manager set-node
```

然后粘贴新的 VLESS 分享链接即可。输入仍然隐藏。

脚本会重新生成配置、校验、启动 Xray 并测试 GitHub / Google。

为了避免旧节点凭据残留，当前版本**不会为节点配置创建长期备份**；同时会清理早期版本产生的 `config.json.bak.*`。

## 只移除个人节点配置

如果只是暂时不用节点，但还想保留 Xray 程序：

```bash
sudo xray-vless-manager remove-node
```

它会：

- 停止并禁用 Xray 服务
- 删除当前 VLESS 节点配置
- 删除旧节点配置备份
- 删除 Docker daemon 的 Xray 代理配置，避免 Docker 继续指向一个已经停止的本地代理
- 保留 Xray 程序和管理工具，之后可再次执行 `set-node`

如果当前 shell 之前执行过 `proxy_on`，再执行：

```bash
proxy_off
```

## 归还 / 转让服务器前彻底移除

执行：

```bash
sudo xray-vless-manager uninstall
```

它会移除：

- VLESS 节点配置及旧备份
- Xray systemd 服务
- Xray 二进制和地域数据
- SOCKS5 / HTTP 本地代理配置
- `proxy_on / proxy_off`
- `xray-proxy-test`
- `xray-vless-manager`
- Docker daemon 的 Xray 代理配置
- 本地保存的安装脚本副本

这样可以避免服务器归还后仍残留可直接使用的个人 VLESS 配置。

> 文件系统或 SSD 的底层数据恢复属于云厂商和存储层问题，普通脚本无法承诺物理层“不可恢复”。这里做的是服务器操作系统层面的配置和凭据清理。

## 平时需要维护白名单吗？

**不需要。**

脚本已经配置成：

```text
国内 / 私网资源  → 直接访问
海外资源          → 海外 VLESS
未知的新域名      → 默认走海外 VLESS
```

普通使用者不需要自己添加网站名单，也不需要手工维护规则文件。

## Docker

如果运行脚本时服务器已经安装 Docker，脚本会自动给 Docker daemon 配置本机代理，主要用于镜像拉取和 Registry 访问。

如果执行 `remove-node` 或 `uninstall`，这份 Docker 代理配置也会自动撤掉，避免留下失效配置。

容器内部是否需要代理，由具体应用部署脚本处理；例如后续 Hindsight 部署不要求使用者自己研究 Docker 网络。

## 一个容易误判的地方

不要使用：

```bash
ping google.com
```

判断当前代理是否正常。`ping` 不经过 HTTP / SOCKS 代理。

请运行：

```bash
xray-vless-manager test
```

## 当前已验证

在腾讯云国内 VPS 上已经实际验证：

- Xray 服务正常启动
- GitHub 经海外节点访问返回 HTTP 200
- Google 经海外节点访问返回 HTTP 200
- Gitee 国内镜像可以高速获取 Xray 安装包
- SOCKS5 / HTTP 本地代理链路正常

Xray 安装包优先从：

```text
https://gitee.com/skyhigh13/xray_bin.git
```

获取。当前默认版本：

```text
v26.3.27
```

支持：

```text
x86_64 / amd64
arm64 / aarch64
armv7
```

## 安全原则

- 不要把 VLESS 分享链接提交到 GitHub、Gitee 或 README。
- 推荐通过脚本隐藏输入节点。
- 本机代理端口只监听 `127.0.0.1`，不直接暴露到公网。
- 不使用 iptables / TProxy 强行劫持整台服务器所有网络流量。
- 不长期保留旧节点配置备份。
- 归还服务器前执行 `sudo xray-vless-manager uninstall`。

---

# 高级说明 / 排障

下面普通使用者可以不看。

## 本地端口

```text
SOCKS5  socks5h://127.0.0.1:10808
HTTP    http://127.0.0.1:10809
```

进入 Xray 后：

```text
私网地址             → DIRECT
中国大陆 IP           → DIRECT
中国大陆域名          → DIRECT
其他 / 未知目标       → VLESS
```

只有明确使用本机代理的应用流量才会进入 Xray；SSH、ICMP 等不会被透明劫持。

## 手动排障

```bash
systemctl status xray --no-pager
journalctl -u xray -n 100 --no-pager
curl -I --socks5-hostname 127.0.0.1:10808 https://www.google.com
curl -I -x http://127.0.0.1:10809 https://github.com
```

## 主要文件

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
    ↓ 失败
SourceForge
    ↓ 失败
GitHub 加速源
    ↓ 失败
官方 GitHub
```

Gitee Raw ZIP 匿名下载曾返回 HTTP 403，因此使用 Git 通道获取镜像文件。在一台腾讯云国内 VPS 上，Gitee Git 通道曾实测约 11 MiB/s。

可以临时指定 Xray 版本：

```bash
XRAY_VERSION=v26.3.27 sudo -E bash setup-xray-vless.sh
```
