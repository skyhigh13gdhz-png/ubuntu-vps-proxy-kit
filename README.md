# Ubuntu VPS Proxy Kit

面向小白的 Ubuntu VPS 初始化、网络诊断与 Xray/3x-ui 部署辅助工具。

> 目标：拿到一台全新的 Ubuntu VPS 后，尽量把重复的人肉检查、依赖安装、环境准备和故障信息采集自动化。项目不绑定 VPS 国家/地区或供应商。

## V1 设计原则

1. **先诊断，后安装**：先判断 VPS 本身是否值得继续折腾，避免把线路/IP 问题误判成 Xray 配置问题。
2. **Ubuntu 优先**：V1 默认支持 Ubuntu 20.04 / 22.04 / 24.04。
3. **缺什么自动补什么**：curl、wget、openssl、socat、jq 等基础依赖缺失时自动安装。
4. **安装与诊断分离**：`diagnose.sh` 只检查，不擅自改系统；`install.sh` 才负责安装。
5. **不假装服务端能证明大陆可达**：VPS 自己 ping/HTTP 出站正常，只能证明 VPS 出站正常，不能证明中国大陆客户端 -> VPS 的入站路径正常。
6. **失败必须可解释**：提供 `collect-report.sh` 生成脱敏诊断报告，方便后续排查和沉淀 FAQ。
7. **幂等优先**：脚本重复运行时尽量不破坏已经存在的配置。

## 推荐流程

```text
全新 Ubuntu VPS
      ↓
01 diagnose.sh
      ↓
判断系统 / IP / DNS / 出站 / 端口 / 防火墙 / Xray / 3x-ui 状态
      ↓
02 install.sh
      ↓
安装基础依赖 + 3x-ui/Xray
      ↓
在 3x-ui 中创建 VLESS + Reality 入站
      ↓
03 verify.sh
      ↓
检查进程、监听端口、配置与 VPS 出站
      ↓
客户端导入节点并实测
      ↓
有问题 → 04 collect-report.sh
```

## 快速开始

```bash
sudo -i
apt update && apt install -y git
git clone https://github.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit.git
cd ubuntu-vps-proxy-kit
chmod +x scripts/*.sh
./scripts/diagnose.sh
./scripts/install.sh
./scripts/verify.sh
```

## 为什么不能完全自动检测“中国大陆直连可用性”？

VPS 位于链路的一端。它可以检查自己的公网 IP、监听端口、防火墙、Xray 状态和互联网出站，但不能仅靠自己证明“中国大陆某运营商当前能否连接这个 IP:端口”。

因此 V1 把检测分成两层：

- **服务端自动检测**：系统、网络、端口、服务、配置、出站等。
- **客户端最终验证**：真实客户端导入节点后连接。只有这一层能验证具体客户端到 VPS 的实际路径。

不强制用户额外做临时网页/手机访问测试；那类测试保留为故障排查的可选手段。

## 文档

- `docs/DESIGN.md`：项目设计与边界
- `docs/INSTALL.md`：从零部署教程
- `docs/TROUBLESHOOTING.md`：排障与 FAQ
- `docs/SECURITY.md`：安全注意事项

## 脚本

- `scripts/common.sh`：公共函数
- `scripts/diagnose.sh`：安装前诊断
- `scripts/install.sh`：依赖及 3x-ui/Xray 安装
- `scripts/verify.sh`：安装后验证
- `scripts/collect-report.sh`：生成脱敏报告

## 当前边界

V1 不尝试自动选择“最优线路”，也不承诺任何 VPS 从任何地区/运营商都可直连。线路质量、跨境路由、IP 状态和运营商策略都可能变化。项目首先解决的是：**把服务器端可自动化的工作自动化，把不可由服务器单方面证明的事情明确留给客户端验证。**
