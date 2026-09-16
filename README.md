# MonkBar (macOS) ⚡️

[![Release](https://img.shields.io/github/v/release/yaoleifly/monk-bar?color=orange&logo=apple)](https://github.com/yaoleifly/monk-bar/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B%20%7C%20Tahoe%2027%2B-black?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%202-blue?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

专为 [monk.party](https://monk.party/) 打造的 macOS 原生状态栏用量与限流监控工具。零第三方依赖，全面支持 macOS 13+ 与 macOS Tahoe (27+)。

> 倡导理念：[《Monk 使用倡议书》](https://monk.party/charter/) · [产品介绍](PRODUCT.md)

---

## 特性一览

1. **状态栏三档显示**：详细（`¥0.40 (1%) · 12d`）、紧凑（`¥0.40`）、仅图标（极简）。
2. **Bento 看板**：今日内部计量熔断条、有效期倒计时、Token 消耗拆解、1h/6h 双窗口防 429 仪表。
3. **临期智能预警**：有效期不足 3 天或已到期时自动提示，置顶续费入口。
4. **原生剪贴板**：输入框全开 `⌘C` / `⌘V` / `⌘A`，自带一键复制与粘贴按钮。
5. **推荐生态**：内置 [Monk-Pi](https://github.com/yaoleifly/monk-pi) 终端 Coding Agent 免安装与 brew 一键命令。
6. **自动检查更新**：启动时自动比对 GitHub Release，支持手动检查，可自由开启/关闭。
7. **macOS Tahoe 原生**：Universal 2 双架构（Apple Silicon + Intel），支持 `⌘-Drag` 拖拽状态栏图标。

---

## 下载与运行

### 直接下载
前往 **[Releases 页面](https://github.com/yaoleifly/monk-bar/releases)** 下载最新的 `MonkUsage-v1.4.1-macOS-Tahoe-Universal.zip`，解压后拖入 `/Applications` 即可。

### 本地编译

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

- 凭据仅存储在本机沙盒：`~/Library/Application Support/MonkUsage/config.json`，绝不上报。
- 环境变量注入：`MONK_EMAIL="your@email.com" MONK_TRADENO="MK..."`。
- 官方规定每次查询计算一次用量，本工具默认手动刷新（`⌘R`），后台轮询安全下限为 5 分钟，具备 ETag 304 缓存。

---

## 许可

[MIT License](LICENSE) © 2026 Yaolei
