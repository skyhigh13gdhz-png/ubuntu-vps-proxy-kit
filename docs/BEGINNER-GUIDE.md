# 小白从 0 搭建 Ubuntu VPS 直连节点

## 你需要准备

- 一台全新的 Ubuntu 22.04 / 24.04 VPS；地区不限。
- VPS 公网 IPv4。
- root 密码或 SSH Key。
- Mac/Windows 电脑用于 SSH。
- Shadowrocket 等客户端用于最终导入和测试。

## 第一步：SSH 登录

```bash
ssh root@你的VPS_IP
```

## 第二步：下载工具包

```bash
git clone https://github.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit.git
cd ubuntu-vps-proxy-kit
chmod +x setup.sh scripts/*.sh
./setup.sh
```

选择：

```text
1. New VPS Setup (guided)
```

脚本会自动：

- 检查 Ubuntu 版本；
- 安装缺失的诊断工具；
- 检查公网 IP、路由、DNS、时间、端口和已有服务；
- 安装 3X-UI/Xray（使用官方安装器）；
- 安装并验证 Unbound；
- 最后进行健康检查。

## 第三步：在 3X-UI 创建 Reality 入站

v1.0 仍保留这一小段人工配置，避免脚本猜错 target/SNI。

推荐基础参数：

```text
Protocol: VLESS
Port: 443
Transport: RAW/TCP
Security: Reality
Flow: None / Disabled
uTLS fingerprint: chrome
```

Reality target/SNI 不要机械照抄历史域名；请选择当前可用、合理的 TLS 目标。

保存后确认：

```bash
ss -ltnp | grep ':443 '
```

## 第四步：生成客户端链接

```bash
bash scripts/04_generate_client_notes.sh
```

按提示填入 3X-UI 显示的：

- UUID
- SNI
- Reality Public Key
- Short ID

脚本会输出 VLESS URI 和二维码，可导入 Shadowrocket。

## 第五步：实际测试

导入后先打开 Google / YouTube 等网页。如果可以正常访问，再测试实际业务。

如果最终客户端连不上，不要重装。运行：

```bash
./setup.sh
```

选择：

```text
7. Advanced diagnostics
```

只有到这一步，才需要做大陆手机反向 TCP 测试、tcpdump、路由等深度排障。
