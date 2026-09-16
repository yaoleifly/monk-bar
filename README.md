# MonkBar (macOS) ⚡️

[![Release](https://img.shields.io/github/v/release/yaoleifly/monk-bar?color=orange&logo=apple)](https://github.com/yaoleifly/monk-bar/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B%20%7C%20Tahoe%2027%2B-black?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%202%20(arm64%20%2B%20x86__64)-blue?logo=apple)](https://github.com/yaoleifly/monk-bar)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

专为 [monk.party](https://monk.party/) 打造的 macOS 极致体验菜单栏用量与限流监控小工具。纯原生 Swift + SwiftUI 打造，严格遵循 Apple Human Interface Guidelines 设计规范，零第三方依赖。**全面原生适配 macOS Tahoe (macOS 27+) 及 macOS 13+**。

> 📖 **产品初衷与共建约定**：建议在使用前阅读 [《Monk 使用倡议书》](https://monk.party/charter/) 与根目录 [PRODUCT.md](PRODUCT.md)。我们主张“少一点浪费，多一点克制”，让有限的模型资源变得透明、可控且持久。

---

## ✨ 核心特性

### 1. 凭据配置原生支持 ⌘C / ⌘V 与一键粘贴
- **系统级快捷键完美支持**：解决了 macOS Accessory 菜单栏程序无法使用 `⌘C`、`⌘V`、`⌘X`、`⌘A` 的经典底层限制，键盘快捷键全开；
- **UI 级一键复制/粘贴**：下单邮箱与订单号（`MK...`）右侧均内嵌独立的「**粘贴**」与「**复制**」快捷按钮，从邮件中复制后一键即可填入。

### 2. 原生支持 macOS Tahoe (macOS 27+) 与 Universal 2 双架构
- **Universal 2 通用双架构**：单文件原生内嵌 `arm64`（Apple Silicon M1-M5）与 `x86_64`（Intel）机器码，在任何 Mac 上均以纯原生模式执行，启动更快且内存极低；
- **macOS Tahoe 动态状态栏与刘海避让**：启用 `item.autosaveName`，支持按住 `⌘`（Command）自由拖拽状态栏图标重排位置并自动持久化。

### 3. 订阅临期提醒与续费引导（< 3 天）
- **智能预警机制**：当月卡剩余有效期不足 3 天（或已到期）时，状态栏自动亮起 `⚠︎` 橙色提示。
- **菜单栏与看板置顶续订入口**：点击状态栏图标首行即显示 `🔥 订阅即将到期 (剩余 X 天) · 点击续订 ↗`，并在监控中心顶部展示醒目的燃橙续费卡片，直达 [monk.party](https://monk.party/) 续费。

### 4. 官方推荐搭配：Monk × Pi (`monk-pi`) 终端 Coding Agent
- **开箱即用 · 零配置终端编程助手**：将 Monk 的 100 万上下文与 Pi 极速终端 Agent 深度结合。
- **预置专属优化**：默认适配 `monk-coding` 主力编程模型，无需手写繁琐的 `models.json` 和 `compat` 参数。
- **快速安装运行**：
  - **免安装直接跑 (推荐)**：`npx monk-pi`
  - **Homebrew 安装**：`brew install yaoleifly/tap/monk-pi`
  - 开源仓库：👉 **[yaoleifly/monk-pi](https://github.com/yaoleifly/monk-pi)**

### 5. 状态栏极致视觉与三档显示模式
- **自适应矢量模板图标**：内置 18×18 矢量贝塞尔绘制的僧侣火焰剪影（`isTemplate = true`），根据系统层级与对比度自动反色。
- **高阶 Attributed 数字排版**：采用 Apple 等宽数字字体（`monospacedDigitSystemFont`），主数值醒目、副指标低饱和度弱化，刷新零抖动。
- **三档显示样式，一键切换**（支持菜单栏或设置面板切换）：
  - **详细模式**：`[图标] ¥0.40 (1%) · 12d`（今日用量 + 消耗百分比 + 剩余有效天数）
  - **紧凑模式**：`[图标] ¥0.40`（极简显示今日内部计量）
  - **仅图标模式**：`[图标]`（纯粹无干扰，仅在异常时点缀 `⚠︎`）

### 6. 实时状态与配额中心 (Bento Grid 仪表盘)
- **🔥 今日内部计量熔断仪表 (Daily Fuse)**：大号高光数字 `¥0.40 / ¥30.00` + 动态平滑渐变能量槽（>80% 变红警戒）。
- **⏱️ 订阅有效期与健康度卡片**：倒计时 `12 天 16 小时` 与到期具体时间。
- **📊 Token 吞吐与分流条 (Token Analytics)**：Prompt（输入冷蓝）与 Completion（输出燃橙）双段对比。
- **🛡️ 双滑动窗口限流调度面板 (Rate Limits & Fairness)**：1 小时与 6 小时滑动窗口加权请求与吞吐量监控 + 并发/突发令牌桶胶囊。
- **💻 开发者快速集成卡片**：API Key、Base URL 一键复制，模型标签说明，并内置 [《Monk 使用倡议书》](https://monk.party/charter/) 直达入口。

---

## 📥 下载与安装

### 方式一：直接下载发布包（推荐）
前往 **[Releases 页面](https://github.com/yaoleifly/monk-bar/releases)** 下载最新的 `MonkUsage-v1.3.1-macOS-Tahoe-Universal.zip`，解压后将 `Monk 用量.app` 拖入 `/Applications`（应用程序）即可。

### 方式二：本地一键构建

```bash
git clone https://github.com/yaoleifly/monk-bar.git
cd monk-bar
./build.sh
open build/MonkUsage.app
```

> **首次配置**：启动后将自动弹起原生设置窗口供输入下单邮箱与订单号（MK...）。平时可随时在菜单栏点击「**设置账号…**」（快捷键 `⌘,`）呼出。

---

## 💻 命令行与脚本调用

本程序内置 CLI 多模式，适合集成到 Raycast、Alfred、终端提示符或自动化脚本：

```bash
# 一行摘要输出（格式化今日用量、窗口限额、剩余天数）
./build/MonkUsage.app/Contents/MacOS/monk-usage --text

# 原样输出 monk.party 官方接口返回的完整 JSON
./build/MonkUsage.app/Contents/MacOS/monk-usage --json

# 查看配置文件路径
./build/MonkUsage.app/Contents/MacOS/monk-usage --config

# 运行内置自检
./build/MonkUsage.app/Contents/MacOS/monk-usage --selfcheck
```

---

## 🔒 隐私与安全性

- 凭据仅存储在本机沙盒路径：`~/Library/Application Support/MonkUsage/config.json`，绝不上报任何第三方服务器。
- 支持环境变量临时注入（适用于自动化环境）：
  ```bash
  export MONK_EMAIL="your@email.com"
  export MONK_TRADENO="MK..."
  ```
- 官方提示「一次查询计算一次今日用量」，本工具严守此规范，默认以手动刷新（`⌘R`）为主，定时轮询下限定为 5 分钟，且具备内存 ETag 304 缓存优化。

---

## 📄 许可与参考

- **产品理念文档**：[PRODUCT.md](PRODUCT.md)
- **《Monk 使用倡议书》**：[https://monk.party/charter/](https://monk.party/charter/)
- **开源许可证**：[MIT License](LICENSE) © 2026 Yaolei
