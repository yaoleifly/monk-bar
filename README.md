# MonkBar (macOS) ⚡️

[![Release](https://img.shields.io/github/v/release/yaoleifly/monk-bar?color=orange&logo=apple)](https://github.com/yaoleifly/monk-bar/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B%20%C2%B7%20Tahoe%2026%20%C2%B7%20Golden%20Gate%2027-black?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%202-blue?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

专为 [monk.party](https://monk.party/) 打造的 macOS 原生状态栏用量与限流监控工具。零第三方依赖。部署目标 macOS 13+；通用二进制含 Intel 切片（macOS 13–26），macOS 27 Golden Gate 走 arm64。

> 倡导理念：[《Monk 使用倡议书》](https://monk.party/charter/) · [产品介绍](PRODUCT.md) · [帮助中心](https://monk.party/help/)

当前服务（2026-10）：Base URL `https://monk.party/v1`。付费 Key（`sk-monk-*`）可调用 `monk`、`monk-fast`、`monk-coding`、`monk-free`。月卡支付宝 ¥30 / 30 天，或 Stripe $5 / 30 天；下单邮箱域名含 `edu` 九折。用量在 [账户页](https://monk.party/account/) 用下单邮箱查询，完整 Key 只在购买邮件里。

---

## 特性一览

1. **邮箱即查 & 多卡切换**：与官网账户页同一接口，只提交下单邮箱；名下多张未过期的卡会在看板顶部切换。
2. **状态栏三档显示**：详细（`¥0.00 (0%) · 25d`）、紧凑（`¥0.00`）、仅图标（极简）。今日内部计量的上限以接口返回为准（公开默认 200，UTC 00:00 清零）。
3. **Bento 看板**：今日内部计量、有效期、近 14 天 Token、1 小时 / 6 小时加权次数与输入 Token。
4. **连通性诊断 (Ping)**：用本机保存的完整 Key 探测 `monk-fast`。查询接口不再下发完整 Key。
5. **临期提醒**：不足 3 天或已到期时提示，续费入口打开账户页（同一把 Key 顺延 30 天）。
6. **原生剪贴板**：输入框支持 `⌘C` / `⌘V` / `⌘A`，自带复制与粘贴。
7. **推荐生态**：内置 [Monk-Pi](https://github.com/yaoleifly/monk-pi) 的 `npx` 与 Homebrew 命令。
8. **检查更新**：启动时比对 GitHub Release，可手动检查，也可关掉。
9. **状态栏图标**：18×18 模板图标，支持 `⌘-Drag` 拖拽排序。

---

## 下载与运行

### 直接下载

到 **[Releases](https://github.com/yaoleifly/monk-bar/releases)** 下载最新的 `MonkUsage` 压缩包，解压后拖入 `/Applications`。

### 本地编译

需要 macOS 与 Xcode 命令行工具（`swiftc`、`iconutil`、`lipo`）。

```bash
git clone https://github.com/yaoleifly/monk-bar.git
cd monk-bar
./build.sh
open build/MonkUsage.app
```

---

## 命令行调用

```bash
./build/MonkUsage.app/Contents/MacOS/monk-usage --text        # 一行摘要
./build/MonkUsage.app/Contents/MacOS/monk-usage --json        # 完整 JSON
./build/MonkUsage.app/Contents/MacOS/monk-usage --config      # 配置文件路径
./build/MonkUsage.app/Contents/MacOS/monk-usage --selfcheck   # 内置自检
```

---

## 隐私与存储

- 凭据只写在本机 `~/Library/Application Support/MonkUsage/config.json`，不会上报。
- 用量查询只提交邮箱，以及可选的订单号：`POST https://monk.party/monk-api/lookup-order`。
- 完整 Key 不是查询结果的一部分。若要在菜单栏里测连通性，把购买邮件中的 `sk-monk-…` 填进「本机 Key」，或设置环境变量 `MONK_API_KEY`。这个值只用于发往 `https://monk.party/v1/chat/completions` 的探测，不会放进用量查询。
- 也可用 `MONK_EMAIL`、`MONK_TRADENO` 注入邮箱和订单号。
- 默认手动刷新（`⌘R`）。打开后台刷新后间隔 5 分钟；响应若带 ETag，未变化时走 304。

---

## 许可

[MIT License](LICENSE) © 2026 Yaolei
