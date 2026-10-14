# MonkBar 产品介绍

> “少一点浪费，多一点克制。我希望 Monk 可以跑得久一点。”  
> —— 摘自 [《Monk 使用倡议书》](https://monk.party/charter/)

---

## 为什么有 MonkBar？

[Monk](https://monk.party/) 是面向编码 Agent 的 OpenAI 兼容融合接口。付费 Key（`sk-monk-*`）可以调用四条融合模型：`monk`（默认，质量优先）、`monk-fast`（更快的日常对话）、`monk-coding`（编码 / Agent）、`monk-free`（每把付费 Key 都能用）。Base URL 是 `https://monk.party/v1`。

月卡支付宝 ¥30 / 30 天，或 Stripe $5 / 30 天。下单邮箱域名含 `edu` 时九折（支付宝 ¥27，Stripe $4.50）。

在 [Monk-Pi](https://github.com/yaoleifly/monk-pi)、Cursor 这类工具里，调用太密会碰到 429，或者打满当日内部计量。计量按 UTC 日清零，上限以查询结果为准（公开说明里的当日上限是 200）。

**MonkBar** 把这些数字放在状态栏里：还剩几天、今天用了多少、1 小时和 6 小时窗口走到哪了。完整 Key 不在查询结果里，只显示末四位；密钥仍以购买邮件为准。

---

## 核心特性

- **内部计量**：当日 `dailyCost / dailyLimit`，超过八成变红，UTC 00:00 清零。
- **临期**：不足 3 天时状态栏出现 `⚠︎`。续费打开 [账户页](https://monk.party/account/)，在原到期日后续 30 天，Key 不变。
- **双窗口**：1 小时与 6 小时的加权次数、输入 Token。普通请求权重 1，输入超过 3.2 万 Token 计 2，超过 8 万计 4。
- **近 14 天 Token**：输入和输出分开看。
- **四个模型名**：看板上列出 `monk`、`monk-fast`、`monk-coding`、`monk-free`，避免还按旧的三条来配客户端。
- **Monk-Pi**：终端里 `npx monk-pi`，或 `brew install yaoleifly/tap/monk-pi`。
- **系统版本**：macOS 13 起可用。26 是 Tahoe，27 是 Golden Gate（仅 Apple 芯片）。

---

## 相关链接

- [《Monk 使用倡议书》](https://monk.party/charter/)
- [Monk 官网](https://monk.party/)
- [查询用量](https://monk.party/account/)
- [帮助中心](https://monk.party/help/)
- [Monk-Pi (GitHub)](https://github.com/yaoleifly/monk-pi)
- [MonkBar (GitHub)](https://github.com/yaoleifly/monk-bar)
- [下载最新版](https://github.com/yaoleifly/monk-bar/releases)
