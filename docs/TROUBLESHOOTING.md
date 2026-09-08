# Troubleshooting / FAQ

## 1. 节点完全连不上，先查什么？

先运行：

```bash
sudo ./setup.sh
# 选择 Advanced diagnostics
```

判断顺序：

1. 443 是否监听；
2. Ubuntu 本机 firewall 是否阻断；
3. 云厂商 Security Group / Cloud Firewall；
4. Reality 参数是否匹配；
5. 必要时做 Mainland TCP Verification。

## 2. tcpdump 看到 SYN 和 SYN-ACK，但没有 ACK

这是重要信号。服务端已经收到客户端 SYN，也已经把 SYN-ACK 发出；如果客户端始终不完成握手，问题可能在 VPS 之外的路径、IP/网段过滤或云厂商网络层。不要第一时间改 MTU、rp_filter、offload。

## 3. `ping` 不通是不是节点坏了？

不是。ICMP 与 TCP 443 不是一回事，很多运营商/终端不回复 ICMP。应以 TCP/HTTPS 实测为准。

## 4. Whoer DNS 显示奇怪国家怎么办？

先检查：

```bash
cat /etc/resolv.conf
systemctl status unbound --no-pager
dig @127.0.0.1 example.com
```

如果 resolv.conf 被改回 8.8.8.8/8.8.4.4，可运行 `scripts/03_setup_unbound.sh` 修复。

## 5. Mac `dig` 显示 198.18.0.x 是 DNS 泄漏吗？

通常不是。Shadowrocket Fake-IP/TUN 会使用 `198.18.0.0/15` 保留地址接管 DNS/连接。需要结合 VPS 端 Unbound 和抓包判断真实上游。

## 6. 3X-UI 面板要不要直接暴露公网？

不建议长期暴露。优先通过 SSH Tunnel 访问管理面板。不要让本项目自动修改 SSH 安全策略；先保证救援通道可靠。

## 7. 为什么不自动修改 rp_filter / TSO / GSO / GRO？

因为这些属于底层网络调优项，不应该成为“小白安装”的默认动作。历史案例中即使把它们改掉，真正的 IP 可达性问题也不会消失。
