# History & Lessons

本文件记录项目设计背后的真实事故，避免以后只记住“最终配置”却忘记“为什么”。

## Case: VPS 本机完全正常，但大陆 TCP 握手不完成

曾有一台 Evoxt VPS 使用 IPv4 `23.27.113.107`。中国移动/电信访问 80/443/944x 时，服务端 tcpdump 能看到：

```text
Client -> SYN
VPS    -> SYN-ACK
Client -> (no final ACK)
```

当时逐项排查过：Xray/Reality、端口、iptables/nftables、policy routing、MTU、rp_filter、TSO/GSO/GRO、路由等，均没有解决。

Evoxt 工单最终判断旧 IP 被中国侧防火墙封锁，并更换为 `23.26.204.84`。保持服务器与 Reality 主要配置不变，仅更换公网 IP 后：

- 中国移动访问临时 `nc:80` 能收到完整 HTTP GET；
- 原 VLESS + REALITY 节点仅改服务器 IP 即恢复 Google 访问；
- 证明核心问题是旧 IP 的大陆可达性，而不是 Linux 配置。

### 结论

当出现“SYN 到、SYN-ACK 出、最终 ACK 不回来”时，不要继续无止境修改 Xray 或内核参数。优先考虑：

- IP/网段被过滤；
- 上游/回程问题；
- 云厂商网络层；
- 大陆侧路径差异。

## Case: 服务商换 IP 后 DNS 变成 Google / India

更换公网 IP 后，`/etc/resolv.conf` 被服务商网络初始化恢复为：

```text
nameserver 8.8.8.8
nameserver 8.8.4.4
```

Whoer 随后显示 DNS 为 Google/India。确认 Unbound 正常运行后，将 resolv.conf 改回：

```text
nameserver 127.0.0.1
```

并抓包确认 Unbound 从 VPS 新公网 IP 向不同权威 DNS 直接递归，Whoer DNS 随后恢复为 VPS/Malaysia。

### 结论

换 IP、重装或服务商网络维护后，第一时间检查 `/etc/resolv.conf`。不要仅凭浏览器检测页的 DNS 国家就乱改网络。

## Case: Fake-IP 导致 ping/curl 指标误读

Shadowrocket TUN/Fake-IP 模式下，`dig`/`ping` 可能看到 `198.18.0.0/15` 保留地址，毫秒级 ping 只是本地虚拟接口，不是大陆到 VPS 的真实 RTT。

### 结论

不要用 Fake-IP 环境下的 ping 直接评价跨境链路。更应结合实际 HTTPS、Speedtest、VPS 侧 traceroute/tcpdump 判断。
