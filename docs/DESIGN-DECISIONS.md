# Design Decisions

## 1. Ubuntu-only v1

第一版只面向 Ubuntu 22.04/24.04。减少跨发行版分支，优先把可靠性做好。

## 2. 不把大陆手机 TCP 测试做成安装必经步骤

VPS 自己无法 100% 证明“大陆客户端一定能访问自己”，但强制用户在安装中途关闭代理、拿手机点临时 URL 会明显降低自动化体验。因此正常流程只做服务端预检；实际节点导入客户端后即可完成更完整的端到端验证。只有连接失败时才进入 Mainland TCP Verification。

## 3. 不写死 Reality target/SNI

历史上使用过 `www.apple.com`，面板也出现过风险提示。单个 target 的可用性和风险会变化，因此脚本不把某个域名当成永恒默认值。v1 由用户在 3X-UI 中选择；后续版本再考虑做 target scanner。

## 4. 默认 Flow=None

在真实测试中 Vision 曾引入兼容性/排障复杂度。v1 面向小白，先采用更简单且已经验证可工作的配置。

## 5. Unbound 采用本机递归

目标是让 VPS 自己通过 `127.0.0.1:53` 进行递归解析，而不是默认依赖 Google/Cloudflare 公共 DNS。切换 `/etc/resolv.conf` 前必须先验证 Unbound；失败自动恢复。

## 6. 不用 chattr +i 锁死 resolv.conf

云厂商更换 IP 或维护网络时可能重写 resolv.conf。强制 immutable 可能干扰正常网络初始化。v1 采用健康检查 / Repair 思路，而不是锁死系统文件。

## 7. 不在正常安装中修改内核网络参数

MTU、rp_filter、TSO/GSO/GRO 等只用于高级诊断。历史排障已经证明“看到异常就改 sysctl”很容易把问题复杂化，且真实根因可能是 IP/上游网络。
