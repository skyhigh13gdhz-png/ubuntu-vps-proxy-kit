# 国内 VPS 使用海外 VLESS 的 Xray 引导脚本

这个分支用于把国内 Ubuntu / Debian / CentOS 类 VPS 配置成：

- 私网和中国大陆流量：直连
- 其他流量：经本机 Xray 转到海外 VLESS 节点
- 本机提供 SOCKS5 / HTTP 代理给 curl、Git、Docker、Hindsight 等程序使用

> 注意：这不是透明代理。只有明确连接到本机 SOCKS5 / HTTP 代理的程序，才会进入 Xray 的分流规则。`ping` 使用 ICMP，不会经过 SOCKS/HTTP 代理。

## 一键安装

推荐直接执行：

```bash
sudo bash setup-xray-vless.sh
```

脚本会隐藏输入 VLESS 分享链接，避免把链接直接写进 shell history。

也可以显式传参：

```bash
sudo bash setup-xray-vless.sh '你的完整VLESS链接'
```

如果使用传参方式，VLESS 链接必须使用单引号包住，因为里面通常包含 `&` 等 shell 特殊字符。

## 脚本会做什么

脚本自动完成：

1. 安装 curl、git、python3、jq、unzip 等依赖。
2. 根据 CPU 架构选择 Xray 包：
   - `x86_64 / amd64` → `Xray-linux-64.zip`
   - `aarch64 / arm64` → `Xray-linux-arm64-v8a.zip`
   - `armv7` → `Xray-linux-arm32-v7a.zip`
3. 优先从国内 Gitee 二进制镜像仓库获取 Xray。
4. 如果 Gitee 不可用，再依次尝试 SourceForge、GitHub 加速源和官方 GitHub。
5. 如果 Gitee 仓存在 `.dgst` 文件，会进行 SHA256 校验，同时再做 ZIP 完整性校验。
6. 解析常见 VLESS 参数，包括 TCP / WS / gRPC / XHTTP，以及 TLS / REALITY。
7. 安装并启用 `xray.service`，设置开机自启。
8. 创建本地 SOCKS5 / HTTP 代理。
9. 创建 shell 代理开关和快速测试命令。
10. 如果系统已经安装 Docker，则自动给 Docker daemon 配置本机 Xray HTTP 代理。

## Xray 下载源

目前默认 Xray 版本：

```text
v26.3.27
```

国内优先镜像：

```text
https://gitee.com/skyhigh13/xray_bin.git
```

镜像仓按照 Xray 版本建立分支，例如 `v26.3.27`，其中保存对应架构的官方 Xray Release 二进制和 `.dgst` 校验文件。

可以临时指定其他版本：

```bash
XRAY_VERSION=v26.3.27 sudo -E bash setup-xray-vless.sh
```

前提是 Gitee 镜像仓已有同名版本分支；如果没有，会进入备用下载源。

### 国内 VPS 实测

在腾讯云国内 VPS 上，直接下载 GitHub Release 和多个 GitHub 加速站曾出现超时、403、429 或只有几十 KB/s 的情况。

同一台服务器通过 Gitee `git clone` 获取 `xray_bin` 仓库时，实测约：

```text
57.28 MiB
11.05 MiB/s
7.756 秒
```

因此当前脚本采用 Gitee Git 通道作为国内首选下载方式，而不是 Gitee Raw URL。Gitee Raw 对 ZIP 文件的匿名访问测试曾返回 HTTP 403。

## 本地代理端口

安装完成后：

```text
SOCKS5  socks5h://127.0.0.1:10808
HTTP    http://127.0.0.1:10809
```

端口只监听 `127.0.0.1`，不会直接暴露到公网。

## Xray 内部分流规则

进入 Xray 的流量默认按下面规则处理：

```text
私网地址             → DIRECT
中国大陆 IP           → DIRECT
中国大陆域名          → DIRECT
其他流量             → VLESS
```

这里的关键点是：**只有已经进入 10808 / 10809 的流量才会使用这些分流规则。**

例如下面的普通命令默认不会自动进入 Xray：

```bash
curl https://github.com
ping www.google.com
```

## Shell 中使用代理

脚本安装：

```text
/etc/profile.d/xray-proxy.sh
```

重新登录 shell 后可以直接使用：

```bash
proxy_on
```

这会给当前 shell 设置：

```text
HTTP_PROXY / HTTPS_PROXY → http://127.0.0.1:10809
ALL_PROXY                → socks5h://127.0.0.1:10808
```

关闭：

```bash
proxy_off
```

如果当前 shell 是脚本安装前已经打开的，可以先执行：

```bash
source /etc/profile.d/xray-proxy.sh
```

再执行 `proxy_on`。

这种方式不会粗暴地把整台服务器永久设置成全局代理，需要访问海外资源时再打开即可。

## 快速验证

脚本会安装：

```bash
xray-proxy-test
```

它会检查：

- Xray systemd 服务状态
- Google 是否能通过 SOCKS5 访问
- GitHub 是否能通过 HTTP 代理访问
- 当前代理出口 IP

也可以手动验证：

```bash
curl -I --socks5-hostname 127.0.0.1:10808 https://www.google.com
```

或：

```bash
curl -I -x http://127.0.0.1:10809 https://github.com
```

测试中已经确认 Google 返回 `HTTP/2 200`，GitHub 返回 `HTTP 200`，说明 VLESS 代理链路工作正常。

### 为什么 `ping google.com` 仍然可能 100% 丢包？

这是正常现象。

`ping` 使用 ICMP，而当前方案提供的是 SOCKS5 / HTTP 应用层代理。ICMP 不会走 10808 / 10809，因此不能用 `ping` 判断 Xray 是否工作。

判断代理是否正常应该使用 `curl`、Git、Docker pull 或实际应用请求。

## Docker

如果执行脚本时系统已经安装 Docker，脚本会创建：

```text
/etc/systemd/system/docker.service.d/xray-proxy.conf
```

让 Docker daemon 的 HTTP / HTTPS 请求通过：

```text
http://127.0.0.1:10809
```

这主要用于 Docker Registry / image pull 等 daemon 出站请求。

需要注意：**Docker daemon 使用代理，不代表容器内部自动继承代理。**

后续给 Hindsight 等容器配置代理时，应根据应用需要单独传入 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`，或采用合适的 host / gateway 网络方式。

如果 Docker 是在执行本脚本之后才安装，可以重新运行脚本，或者手动补 Docker systemd drop-in。

## systemd 服务与排查

查看 Xray：

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

配置文件：

```text
/usr/local/etc/xray/config.json
```

Xray 二进制：

```text
/usr/local/bin/xray
```

Geo 数据：

```text
/usr/local/share/xray/
```

## 安全说明

- VLESS 链接包含连接凭据，不要提交到 GitHub / Gitee，也不要写进 README。
- 推荐运行脚本后通过隐藏输入框粘贴 VLESS URI。
- SOCKS5 和 HTTP inbound 默认仅绑定 `127.0.0.1`。
- 不建议为了方便直接把 10808 / 10809 监听到 `0.0.0.0`。
- 当前方案刻意不做 iptables / TProxy 全局透明劫持，以减少 SSH、apt、国内业务流量受到代理故障影响的风险。
