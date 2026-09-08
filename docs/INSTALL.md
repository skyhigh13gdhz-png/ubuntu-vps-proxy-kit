# 从零开始：Ubuntu VPS 部署教程

## 0. 你需要什么

- 一台拥有公网 IPv4 的 Ubuntu VPS；
- root 权限或可 sudo 的账号；
- SSH 客户端；
- 最终使用节点的客户端设备。

VPS 可以位于任意国家/地区。本项目不假设特定供应商。

## 1. 登录 VPS

```bash
ssh root@你的VPS_IP
```

如果供应商默认不是 root：

```bash
sudo -i
```

## 2. 下载项目

```bash
apt update
apt install -y git
git clone https://github.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit.git
cd ubuntu-vps-proxy-kit
chmod +x scripts/*.sh
```

## 3. 安装前诊断

```bash
./scripts/diagnose.sh
```

重点看：Ubuntu 是否识别正确、是否拿到公网 IPv4、DNS/HTTPS 出站是否正常、当前有哪些端口监听、是否已有 x-ui/Xray。

不要因为 VPS 能 ping Google 或 curl Google 就得出“大陆一定能直连此 VPS”的结论，这是两个方向的链路。

## 4. 安装

```bash
./scripts/install.sh
```

脚本会先补齐基础依赖，然后调用 3x-ui 上游安装程序。已经存在 x-ui 时默认不覆盖。

## 5. 创建节点

进入 3x-ui 后创建 VLESS + Reality 入站。典型方向：

- Protocol：VLESS
- Transport：RAW/TCP（以当前 3x-ui/Xray UI 为准）
- Security：Reality
- uTLS：Chrome
- 端口：优先选择你明确开放且未被占用的端口；443 常用但不是强制
- Reality target/SNI：选择稳定、支持 TLS 1.3、从 VPS 可正常访问的目标

不要照抄他人的 UUID、Reality 私钥、公钥、Short ID 或 SpiderX。

## 6. 安装后验证

```bash
./scripts/verify.sh
```

它确认服务器端服务、监听和出站。然后把节点导入你的真实客户端进行最终连接测试。

## 7. 出问题时

不要先随机改 Reality、端口、SNI、传输方式和系统参数。先执行：

```bash
./scripts/collect-report.sh
```

根据报告判断属于哪一层，再处理。

## 8. 更新项目

```bash
cd ubuntu-vps-proxy-kit
git pull
```

更新脚本不会等同于自动升级你已经运行的 3x-ui/Xray 服务。
