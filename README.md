# 国内 VPS 海外网络一键配置

这个分支的目标很简单：**让国内 VPS 在需要访问海外服务时自动通过海外 VLESS 节点，同时国内资源保持直连。**

日常使用不需要理解 Xray、geoip、geosite、SOCKS、路由规则这些概念。脚本会自动处理。

## 最简单的用法

把脚本放到服务器后执行：

```bash
sudo bash setup-xray-vless.sh
```

然后按照提示粘贴你的 VLESS 分享链接即可。输入过程是隐藏的，不会直接显示在终端里。

安装完成后，如果看到类似：

```text
SUCCESS: Xray VLESS path, GitHub and Google access are working.
```

说明代理链路已经正常。

## 安装后你需要知道的只有 3 个命令

检查代理是否正常：

```bash
xray-proxy-test
```

当前终端需要访问海外资源时：

```bash
proxy_on
```

不需要代理时：

```bash
proxy_off
```

如果刚安装完后当前终端还找不到 `proxy_on`，执行一次：

```bash
source /etc/profile.d/xray-proxy.sh
```

## 平时需要维护白名单吗？

**不需要。**

脚本已经配置成：

```text
国内 / 私网资源  → 直接访问
海外资源          → 海外 VLESS
未知的新域名      → 默认走海外 VLESS
```

国内地址的识别数据随 Xray 安装包一起安装，普通使用者不需要自己添加网站名单，也不需要理解或手工维护规则文件。

以后部署 GitHub、Docker、Hindsight、LLM API 等新服务时，也不需要因为出现一个新域名就回来加白名单。

## Docker

如果运行脚本时服务器已经安装 Docker，脚本会自动给 Docker daemon 配置本机代理，主要用于镜像拉取和 Registry 访问。

如果 Docker 是之后才安装的，重新运行一次本脚本即可补上配置。

容器内部是否需要代理，由具体应用决定；后续部署 Hindsight 等服务时由对应部署脚本处理，不要求普通使用者手动折腾。

## 一个容易误判的地方

不要使用：

```bash
ping google.com
```

来判断代理是否正常。

`ping` 不会经过当前的 HTTP / SOCKS 代理，因此即使 100% 丢包，代理也可能完全正常。

请直接运行：

```bash
xray-proxy-test
```

## 当前已验证

在腾讯云国内 VPS 上已经实际验证：

- Xray 服务可以正常启动
- GitHub 经海外节点访问返回 HTTP 200
- Google 经海外节点访问返回 HTTP 200
- Gitee 国内镜像可以高速获取 Xray 安装包
- SOCKS5 / HTTP 本地代理链路正常

Xray 安装包优先从国内 Gitee 镜像仓库获取：

```text
https://gitee.com/skyhigh13/xray_bin.git
```

当前默认版本：

```text
v26.3.27
```

支持常见服务器架构：

```text
x86_64 / amd64
arm64 / aarch64
armv7
```

## 安全

- 不要把 VLESS 分享链接提交到 GitHub、Gitee 或 README。
- 推荐直接运行脚本后通过隐藏输入方式粘贴 VLESS 链接。
- 本机代理端口默认只监听 `127.0.0.1`，不会直接暴露到公网。
- 脚本不会使用 iptables / TProxy 强行劫持整台服务器的所有网络流量，因此代理故障不会轻易把 SSH、apt 等基础访问一起拖死。

---

# 高级说明 / 排障

下面内容普通使用者可以不看。

## 工作方式

只有使用本机代理的程序才会进入 Xray：

```text
SOCKS5  socks5h://127.0.0.1:10808
HTTP    http://127.0.0.1:10809
```

进入 Xray 后再进行分流：

```text
私网地址             → DIRECT
中国大陆 IP           → DIRECT
中国大陆域名          → DIRECT
其他 / 未知目标       → VLESS
```

这里使用 Xray 随安装包提供的地域规则数据完成判断。普通使用者无需维护所谓的“国内网站白名单”。

## 为什么不是全局透明代理

当前设计刻意采用应用层代理，而不是直接劫持整台服务器全部流量。

好处是：

- 国内 apt / 软件源可以正常直连
- SSH 不依赖海外节点
- 海外节点异常时不会导致服务器整体断网
- Docker、Hindsight 等服务可以按需使用代理
- 排障更简单

## 手动检查

查看 Xray 服务：

```bash
systemctl status xray --no-pager
```

查看日志：

```bash
journalctl -u xray -n 100 --no-pager
```

重启：

```bash
sudo systemctl restart xray
```

手动测试 Google：

```bash
curl -I --socks5-hostname 127.0.0.1:10808 https://www.google.com
```

手动测试 GitHub：

```bash
curl -I -x http://127.0.0.1:10809 https://github.com
```

## 主要文件位置

```text
/usr/local/bin/xray
/usr/local/etc/xray/config.json
/usr/local/share/xray/
/etc/profile.d/xray-proxy.sh
/etc/systemd/system/xray.service
```

如果 Docker 已安装，还会有：

```text
/etc/systemd/system/docker.service.d/xray-proxy.conf
```

## Xray 下载策略

国内 VPS 直接下载 GitHub Release 曾实测出现超时、403、429 或极低速度，因此脚本采用：

```text
Gitee 二进制镜像
    ↓ 失败
SourceForge
    ↓ 失败
GitHub 加速源
    ↓ 失败
官方 GitHub
```

Gitee Raw ZIP 匿名下载曾返回 HTTP 403，因此使用 `git clone --depth 1 --branch <版本>` 获取镜像文件。

在一台腾讯云国内 VPS 上，Gitee Git 通道曾实测约 11 MiB/s。

## 版本覆盖

可以临时指定 Xray 版本：

```bash
XRAY_VERSION=v26.3.27 sudo -E bash setup-xray-vless.sh
```

前提是 Gitee 镜像仓有对应版本分支；否则脚本会尝试备用下载源。
