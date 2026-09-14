任何国内 Ubuntu/Debian/CentOS 类 VPS，基本就是把脚本传上去，然后执行：
sudo bash setup-xray-vless.sh '你的完整VLESS链接'

注意 VLESS 链接一定要用单引号包住，因为里面通常有 & 等 shell 特殊字符。

这个版本会自动完成：安装依赖和 Xray、解析你的 vless:// 分享链接、识别常见 TCP/WS/gRPC/XHTTP + TLS/REALITY 参数、配置 systemd 开机自启，并在本机开启：
SOCKS5: 127.0.0.1:10808
HTTP:   127.0.0.1:10809

路由规则默认就是我们刚才讨论的模式：
私网地址           → 腾讯 VPS 直接访问
中国大陆 IP/域名    → 腾讯 VPS 直接访问
其他流量           → 外网节点 VLESS