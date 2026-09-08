# Architecture

## 目标用户

没有 Linux 基础、拿到一台全新 Ubuntu VPS，希望快速得到可在 Shadowrocket 等客户端使用的 VLESS + REALITY 节点的人。

## 正常安装路径

```text
Fresh Ubuntu VPS
  -> setup.sh
  -> bootstrap dependencies
  -> server/network precheck
  -> install 3X-UI + Xray
  -> create VLESS + REALITY inbound in panel
  -> setup local Unbound recursion
  -> health check
  -> generate VLESS URI / QR
  -> import into client and test
```

## 故障路径

只有最终客户端连不上时才进入：

```text
Advanced Diagnostics
  -> local listener + tcpdump
  -> Mainland client optional reverse test
  -> distinguish local firewall / provider firewall / route / IP reachability / Xray config
```

## 自动化边界

### 自动处理

- apt 依赖
- 基础系统检测
- Unbound 安装与本地递归配置
- resolv.conf 切换与失败回滚
- 3X-UI 官方安装器调用
- 健康检查
- 诊断报告和日志
- 客户端 URI/二维码辅助生成

### 必须人工确认

- 占用 443 的既有服务如何处理
- 覆盖已有 Xray/3X-UI
- Reality target/SNI
- 防火墙策略变更

### 默认不自动修改

- sshd_config
- 默认路由
- MTU
- rp_filter
- TSO/GSO/GRO
- IPv6 开关
- 云厂商网络层配置
