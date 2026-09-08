# Ubuntu VPS Proxy Kit

面向小白的 Ubuntu VPS 代理搭建与排障工具。目标：拿到一台全新的 Ubuntu VPS 后，用尽可能少的人工操作完成环境检测、依赖安装、3X-UI/Xray、VLESS + REALITY、Unbound DNS、客户端参数整理和最终健康检查。

> 当前 v1.0 目标系统：Ubuntu 22.04 / 24.04 LTS。VPS 地区不限。

## 设计原则

- 能检测的自动检测，缺少普通工具时自动安装。
- 重复执行尽量幂等，不无脑覆盖已有环境。
- 修改重要配置前备份；验证失败时尽量回滚。
- 不默认修改 SSH、默认路由、MTU、rp_filter、TSO/GSO/GRO、IPv6 等底层网络设置。
- 大陆手机反向 TCP 测试不作为正常安装必经步骤，只在节点连不上时进入 Advanced Diagnostics。
- Reality 的 target/SNI 不写死，避免把某个历史配置机械复制到所有 VPS。

## 快速开始

```bash
sudo -i
git clone https://github.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit.git
cd ubuntu-vps-proxy-kit
chmod +x setup.sh scripts/*.sh
./setup.sh
```

正常新机选择 `1. New VPS Setup`。

## 推荐主流程

1. Bootstrap：检查并补齐 curl、dig、traceroute、tcpdump、nc、ethtool、qrencode 等依赖。
2. Pre-check：检查公网 IP、路由、DNS、时间同步、端口、防火墙、已有 Xray/3X-UI/Unbound。
3. 安装 3X-UI：调用官方 MHSanaei/3x-ui 安装脚本，不静默覆盖已有代理栈。
4. 在 3X-UI 创建 VLESS + REALITY 入站：默认 TCP/RAW 443、Flow=None、uTLS=chrome；target/SNI 需根据当前环境选择。
5. Setup Unbound：先验证本机递归，再把 `/etc/resolv.conf` 切到 `127.0.0.1`；失败自动恢复。
6. Health Check：检查 x-ui、443、Unbound、DNS、遗留 nc/tcpdump 和 offload 状态。
7. 生成客户端参数：运行 `scripts/04_generate_client_notes.sh`，输出 VLESS URI 和终端二维码。

## 重要说明

3X-UI 官方当前推荐的一键安装方式为：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

本项目的安装脚本只是对官方安装器做前置检查和结果验证，不自行维护 3X-UI 二进制分发。

## 项目文档

- `docs/BEGINNER-GUIDE.md`：从零开始保姆教程
- `docs/ARCHITECTURE.md`：架构与自动化边界
- `docs/DESIGN-DECISIONS.md`：关键设计决策及原因
- `docs/HISTORY-LESSONS.md`：真实排障案例与踩坑记录
- `docs/TROUBLESHOOTING.md`：FAQ / 故障树
- `docs/ROADMAP.md`：后续版本计划

## 安全提醒

- 不要把 Reality 私钥截图公开。
- 面板长期不建议直接暴露公网；优先使用 SSH Tunnel 管理。
- 本项目不会自动修改 SSH 登录策略。
- 服务商 Cloud Firewall / Security Group 不属于 Ubuntu 本机防火墙，外部端口不通时必须一并检查。
