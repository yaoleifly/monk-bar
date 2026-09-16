# MonkBar 产品介绍

> “少一点浪费，多一点克制。我希望 Monk 可以跑得久一点。”  
> —— 摘自 [《Monk 使用倡议书》](https://monk.party/charter/)

---

## 为什么有 MonkBar？

[Monk](https://monk.party/) 是一项具备公益属性的高性能模型服务，提供顶尖 Flash 融合模型（`monk` / `monk-fast` / `monk-coding`）与 100 万 Token 超长上下文。

在日常使用 Coding Agent（如 [Monk-Pi](https://github.com/yaoleifly/monk-pi)、Cursor 等）时，频繁调用容易触发 429 限流或过早打满每日保险丝。

**MonkBar** 让消耗变得**透明、可控、有敬畏**。常驻状态栏与 Bento 看板，帮助开发者按需使用，守护共享算力。

---

## 核心特性

- **熔断计量透明化**：实时查看当日内部计量（`¥0.40 / ¥30.00`），UTC 00:00 自动重置，>80% 变红预警。
- **订阅临期预警**：有效期不足 3 天时状态栏显示 `⚠︎`，菜单与看板置顶续费入口。
- **双窗口限流保护**：独立展示 1 小时与 6 小时加权请求及输入 Token，避免盲目并发触发 429 惩罚。
- **Token 结构拆解**：Prompt 与 Completion 双段对比，直观优化上下文大小。
- **生态深度整合**：内置 [Monk-Pi](https://github.com/yaoleifly/monk-pi) 终端 Coding Agent 一键安装指南。
- **macOS 原生与 Tahoe 适配**：Universal 2 通用二进制（Apple Silicon + Intel），支持 `⌘-Drag` 自由拖拽排序与 `⌘C` / `⌘V` 剪贴板。

---

## 相关链接

- [《Monk 使用倡议书》](https://monk.party/charter/)
- [Monk 官网](https://monk.party/)
- [Monk 账户与用量](https://monk.party/account/)
- [Monk-Pi (GitHub)](https://github.com/yaoleifly/monk-pi)
- [MonkBar (GitHub)](https://github.com/yaoleifly/monk-bar)
- [下载最新版](https://github.com/yaoleifly/monk-bar/releases)
