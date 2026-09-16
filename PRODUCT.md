# MonkBar 产品介绍与设计理念

> **“少一点浪费，多一点克制。我希望 Monk 可以跑得久一点。”**  
> —— 摘自 [《Monk 使用倡议书》](https://monk.party/charter/)

---

## 一、 为什么有 MonkBar？

[Monk](https://monk.party/) 是一项带有公益性质的高性能融合模型服务。它将顶尖 Flash 模型的速度、低延迟、深度代码推演能力（`monk` / `monk-fast` / `monk-coding`）与 100 万 Token 的超长上下文融为一体，为开发者提供高性价比的推理与 Agent 原生调用。

然而，正如 [《Monk 使用倡议书》](https://monk.party/charter/) 中所写：
> *目前 Monk 提供的模型资源并不是无限的。每一次对话、每一个长任务、每一次 Agent 调用，背后都会真实消耗 Token、并发和计算资源。*

在日常使用 Coding Agent（如 [Monk-Pi](https://github.com/yaoleifly/monk-pi)、Cursor、Cline、Codex 等）时，开发者最常面临两类痛点：
1. **黑盒焦虑**：不知道当天的内部计量保险丝用到了百分之几，不知道当前是否接近 1h/6h 的并发与请求窗口阈值；
2. **意外超限**：无意间的过高并发或密集重试触发了 429 惩罚，既影响了个人开发节奏，也对共享服务器造成了不必要的瞬时峰值冲击。

**MonkBar** 应运而生。它不是为了催促你消耗更多算力，而是为了让有限的模型资源变得**透明、可控、有敬畏**。通过状态栏常驻与 Bento Grid 仪表盘，让每一位开发者对自己的用量心中有数，践行克制与合理调度的精神。

请在开始使用前，完整阅读官方的：  
👉 **[《Monk 使用倡议书》(https://monk.party/charter/)**

---

## 二、 核心功能与产品体验

### 1. 实时透明的「熔断保险丝」与配额中心
- **今日内部计量监控**：实时展示当日内部计量消耗（如 `¥0.40 / ¥30.00`），采用平滑自适应能量槽，并在超过 80% 时温和示警。这是 Monk 保护共享资源的“保险丝”，每日 UTC 00:00 自动清零。
- **订阅有效倒计时**：清晰掌握到期北京时间与天数倒计时。当有效期不足 3 天时，提供优雅的智能续费提醒，避免 Coding Agent 突发断用。
- **Token 吞吐分析**：直观拆解输入 Prompt 与输出 Completion 的分流比例条（如 97.6% vs 2.4%），帮助开发者持续优化 Prompt 上下文裁剪。

### 2. 双滑动窗口防 429 调度仪表（守护公平）
按照 [《Monk 使用倡议书》](https://monk.party/charter/) 中倡导的「按需使用、合理控制长任务、高峰期互相让一让」：
- **1 小时 / 6 小时双窗口状态**：独立计量加权请求次数与输入 Token 吞吐；
- **并发与令牌桶保护胶囊**：随时了解单 Key 2 路并发、全站 8 路并发、短突发容量 20 与每分钟补充 8 次的运行机制；
- 杜绝因脚本盲目并发造成的 429 连环处罚。

### 3. Apple Human Interface Guidelines 极致美学
- **macOS Tahoe (macOS 27+) 与 Universal 2 双架构**：单文件原生支持 Apple Silicon（M1-M5）与 Intel Mac，极致轻量，零 Rosetta 转译损耗；
- **自适应矢量模板图标**：18×18 纯矢量贝塞尔绘制的僧侣火焰剪影，随深色/浅色模式与点击态自动反色；
- **防抖等宽微排版**：`monospacedDigitSystemFont` 确保状态栏数字变动时绝无像素跳动；
- **三档状态栏样式**：详细模式、紧凑模式、仅图标模式随心切换。

### 4. 官方推荐搭配生态
- 原生深度整合官方推荐的终端 Coding Agent 工具：**[Monk × Pi (monk-pi)](https://github.com/yaoleifly/monk-pi)**，支持免安装 `npx monk-pi` 或 `brew install yaoleifly/tap/monk-pi` 一键配置主力编程模型。

---

## 三、 使用约定与共建理念

我们强烈倡导 MonkBar 的每一位用户遵循 [《Monk 使用倡议书》](https://monk.party/charter/) 中的五项共建约定：

1. **按需使用**：能解决问题就好，尽量避免无意义地反复生成、刷 Token。
2. **合理使用长任务**：Coding Agent、超长上下文等任务消耗很大，请尽量控制并发和任务数量。
3. **不要滥用资源**：请勿通过脚本恶意并发、批量跑量、共享账号或进行其他明显超出正常个人使用范围的行为。
4. **高峰期互相让一让**：如果偶尔遇到速度下降、限流或者模型暂时不可用，可以稍等一会儿再试。
5. **发现问题欢迎反馈**：Monk 还在持续迭代，有 Bug、有体验不好的地方，大家一起维护才能跑得更久。

---

## 四、 链接与资源

- **《Monk 使用倡议书》**：[https://monk.party/charter/](https://monk.party/charter/)
- **Monk 官方网站**：[https://monk.party/](https://monk.party/)
- **Monk 账户与用量查询**：[https://monk.party/account/](https://monk.party/account/)
- **Monk-Pi 终端 Coding Agent**：[https://github.com/yaoleifly/monk-pi](https://github.com/yaoleifly/monk-pi)
- **MonkBar 开源仓库**：[https://github.com/yaoleifly/monk-bar](https://github.com/yaoleifly/monk-bar)
- **MonkBar 最新下载**：[https://github.com/yaoleifly/monk-bar/releases](https://github.com/yaoleifly/monk-bar/releases)
