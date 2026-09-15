//
//  monk 用量监控 · macOS 菜单栏小工具（单文件，无依赖）
//
//  用法：
//    monk-usage                 菜单栏常驻
//    monk-usage --text          一行输出（可放 alias / raycast script）
//    monk-usage --json          原样打印接口 JSON
//    monk-usage --config        打印配置文件路径
//    monk-usage --selfcheck     跑内置自检（解码 + 格式化）
//
//  接口：POST https://monk.party/monk-api/lookup-order  body {"email":..,"tradeNo":..}
//  官方提示「一次查询计算一次今日用量」，故自动刷新默认关闭，手动 ⌘R。
//

import AppKit
import Foundation
import SwiftUI

// MARK: - 视觉图标 (Apple HIG 矢量模板与配色)

enum Visuals {
    static let flameOrange = Color(red: 0.95, green: 0.45, blue: 0.08)
    static let flameGold = Color(red: 0.99, green: 0.88, blue: 0.28)
    static let flameDark = Color(red: 0.85, green: 0.28, blue: 0.05)

    /// 菜单栏 18x18 矢量模板图标：僧侣冥想火焰剪影
    /// isTemplate = true 时，macOS 会根据浅色/深色模式及点击态自动反色
    static func makeMenuIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            // 头部圆球 (cx=9.0, cy=13.8, r=2.0)
            let head = NSBezierPath(ovalIn: NSRect(x: 7.0, y: 11.8, width: 4.0, height: 4.0))
            head.fill()

            // 僧袍左翼
            let lPath = NSBezierPath()
            lPath.move(to: NSPoint(x: 3.5, y: 2.5))
            lPath.line(to: NSPoint(x: 5.8, y: 9.8))
            lPath.line(to: NSPoint(x: 9.0, y: 7.2))
            lPath.line(to: NSPoint(x: 7.2, y: 2.5))
            lPath.close()
            lPath.fill()

            // 僧袍右翼
            let rPath = NSBezierPath()
            rPath.move(to: NSPoint(x: 14.5, y: 2.5))
            rPath.line(to: NSPoint(x: 12.2, y: 9.8))
            rPath.line(to: NSPoint(x: 9.0, y: 7.2))
            rPath.line(to: NSPoint(x: 10.8, y: 2.5))
            rPath.close()
            rPath.fill()

            // 僧袍底部轻微闭合弧
            let bPath = NSBezierPath()
            bPath.move(to: NSPoint(x: 3.5, y: 2.5))
            bPath.line(to: NSPoint(x: 7.2, y: 2.5))
            bPath.line(to: NSPoint(x: 10.8, y: 2.5))
            bPath.line(to: NSPoint(x: 14.5, y: 2.5))
            bPath.line(to: NSPoint(x: 9.0, y: 1.5))
            bPath.close()
            bPath.fill()

            // 心灵核心微光镂空 (合十微光)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let core = NSBezierPath()
            core.move(to: NSPoint(x: 9.0, y: 10.0))
            core.line(to: NSPoint(x: 10.3, y: 6.8))
            core.line(to: NSPoint(x: 9.0, y: 3.4))
            core.line(to: NSPoint(x: 7.7, y: 6.8))
            core.close()
            core.fill()

            return true
        }
        img.isTemplate = true
        return img
    }

    /// 获取内置的高清 AppIcon（若未打包则回退为矢量绘制）
    static func appIconImage() -> NSImage {
        let resPath = Bundle.main.bundlePath + "/Contents/Resources/AppIcon_128.png"
        if let img = NSImage(contentsOfFile: resPath) { return img }
        if let appIcon = NSApp.applicationIconImage, appIcon.size.width > 32 { return appIcon }
        return makeMenuIcon()
    }
}

// MARK: - 配置

struct Config: Codable {
    var email: String
    var tradeNo: String
}

enum Cfg {
    static let endpoint = URL(string: "https://monk.party/monk-api/lookup-order")!
    static let accountPage = URL(string: "https://monk.party/account/")!

    static var dir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let d = base.appendingPathComponent("MonkUsage", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var url: URL { dir.appendingPathComponent("config.json") }

    static let template = "{\n  \"email\": \"you@example.com\",\n  \"tradeNo\": \"MK...\"\n}\n"

    static func load() -> Config? {
        let env = ProcessInfo.processInfo.environment
        if let e = env["MONK_EMAIL"], let t = env["MONK_TRADENO"], !e.isEmpty, !t.isEmpty {
            return Config(email: e, tradeNo: t)
        }
        guard let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Config.self, from: data),
              !c.email.isEmpty, !c.tradeNo.isEmpty, !c.email.contains("example.com")
        else { return nil }
        return c
    }

    static func ensureTemplateWritten() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? template.write(to: url, atomically: true, encoding: .utf8)
    }

    static func save(_ c: Config) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? enc.encode(c) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 接口模型

struct UsageWindow: Codable { var w: Double?; var pin: Double? }

struct RateLimit: Codable {
    var limited: Bool?
    var retryAt: String?
    var hour: UsageWindow?
    var six: UsageWindow?
}

struct Fairness: Codable {
    var hourMax: Double?
    var hourPrompt: Double?
    var sixHourMax: Double?
    var sixHourPrompt: Double?
    var inflightPerKey: Double?
    var inflightGlobal: Double?
    var burstCapacity: Double?
    var burstRefillPerMin: Double?
    var penalty429PerMin: Double?
    var penaltyMinutes: Double?
}

struct Tokens: Codable { var prompt: Double?; var completion: Double?; var total: Double? }

struct Order: Codable {
    var apiKey: String?
    var tradeNo: String?
    var status: String?
    var createdAt: String?
    var paidAt: String?
    var expiresAt: String?
    var remainingMs: Double?
    var expired: Bool?
    var soon: Bool?
    var keyActive: Bool?
    var dailyCost: Double?
    var dailyLimit: Double?
    var tokens: Tokens?
    var fairness: Fairness?
    var rateLimit: RateLimit?
    var cooldownUntil: String?
}

struct Root: Codable { var success: Bool?; var order: Order?; var error: String? }

// MARK: - 网络

final class Fetcher {
    // ponytail: 内存 ETag 缓存，进程重启即失效。若要做历史曲线，升级路径是把 order JSON 落 SQLite 并持久化 etag。
    private var etag: String?
    private var cached: Order?
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// completion 固定在主线程回调，参数为 (Order?, 用户可读错误?)
    func lookup(_ cfg: Config, completion: @escaping (Order?, String?) -> Void) {
        var req = URLRequest(url: Cfg.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject:
            ["email": cfg.email, "tradeNo": cfg.tradeNo])
        if cached != nil, let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        session.dataTask(with: req) { [weak self] data, resp, err in
            let main: (Order?, String?) -> Void = { o, e in DispatchQueue.main.async { completion(o, e) } }
            if let err {
                main(nil, "网络错误：\(err.localizedDescription)")
                return
            }
            guard let http = resp as? HTTPURLResponse, let data else {
                main(nil, "响应异常")
                return
            }
            if http.statusCode == 304, let self, let c = self.cached {
                main(c, nil)
                return
            }
            guard let root = try? JSONDecoder().decode(Root.self, from: data) else {
                main(nil, "无法解析响应（HTTP \(http.statusCode)）")
                return
            }
            switch (http.statusCode, root.success, root.order) {
            case (200, true, let o?) where o.apiKey?.isEmpty == false:
                if let tag = http.value(forHTTPHeaderField: "ETag") { self?.etag = tag }
                self?.cached = o
                main(o, nil)
            case (200, true, let o?) where o.status != "paid":
                main(o, "订单未支付或 Key 未下发（status=\(o.status ?? "?")）")
            case (404, _, _):
                main(nil, root.error ?? "订单号与邮箱不匹配。")
            case (429, _, _):
                main(nil, "查询过于频繁（429），稍后再试。")
            default:
                main(nil, root.error ?? "查询失败（HTTP \(http.statusCode)）")
            }
        }.resume()
    }
}

// MARK: - 格式化

enum Fmt {
    static func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v < 10 ? String(format: "¥%.2f", v) : String(format: "¥%.1f", v)
    }

    static func tok(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1e6 { return String(format: "%.2fM", v / 1e6) }
        if v >= 1e3 { return String(format: "%.0fk", v / 1e3) }
        return String(format: "%.0f", v)
    }

    static func num(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func bar(_ used: Double?, _ total: Double?, width: Int = 10) -> String {
        guard let used, let total, total > 0 else { return "—" }
        let f = min(1.0, max(0.0, used / total))
        let n = Int((f * Double(width)).rounded())
        return String(repeating: "▰", count: n) + String(repeating: "▱", count: width - n)
    }

    static func left(_ ms: Double?, expired: Bool) -> String {
        if expired { return "已到期" }
        guard let ms, ms > 0 else { return "—" }
        let t = Int(ms / 1000), d = t / 86_400, h = (t % 86_400) / 3_600
        return d > 0 ? "约 \(d) 天 \(h) 小时" : "约 \(h) 小时"
    }

    static func date(_ iso: String?, zone: String = "Asia/Shanghai") -> String {
        guard let d = parse(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: zone) ?? .current
        return f.string(from: d)
    }

    static func rel(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "—" }
        let s = Int(d.timeIntervalSinceNow)
        if s <= 0 { return "已生效" }
        if s >= 3_600 { return "约 \(s / 3_600) 小时后" }
        return "约 \(max(1, s / 60)) 分钟后"
    }

    static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        if let d = frac.date(from: iso) { return d }
        return plain.date(from: iso)
    }

    private static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// 当前状态：可调用 / 冷却中 / 限流中 / 已停用
func state(_ o: Order) -> (label: String, bad: Bool) {
    let expired = o.expired == true || o.keyActive == false
    if expired { return ("已停用", true) }
    if let cd = Fmt.parse(o.cooldownUntil), cd.timeIntervalSinceNow > 0 {
        return ("冷却中 · " + Fmt.rel(o.cooldownUntil) + "解除", true)
    }
    if o.rateLimit?.limited == true {
        return ("限流中 · " + Fmt.rel(o.rateLimit?.retryAt) + "恢复", true)
    }
    return ("可调用", false)
}

/// 检查订阅有效期是否不足 3 天（或已到期 / 即将到期）
func isExpiringSoon(_ o: Order) -> Bool {
    if o.expired == true || o.keyActive == false { return true }
    if let ms = o.remainingMs, ms > 0 {
        let days = ms / 1000.0 / 86400.0
        return days <= 3.0 || o.soon == true
    }
    return o.soon == true
}

func summaryLine(_ o: Order) -> String {
    let st = state(o)
    return [
        "monk [\(st.label)]",
        "今日 \(Fmt.money(o.dailyCost))/\(Fmt.money(o.dailyLimit)) \(Fmt.bar(o.dailyCost, o.dailyLimit))",
        "1h \(Fmt.num(o.rateLimit?.hour?.w))/\(Fmt.num(o.fairness?.hourMax)) 次 · \(Fmt.tok(o.rateLimit?.hour?.pin))/\(Fmt.tok(o.fairness?.hourPrompt)) in",
        "6h \(Fmt.num(o.rateLimit?.six?.w))/\(Fmt.num(o.fairness?.sixHourMax)) 次 · \(Fmt.tok(o.rateLimit?.six?.pin))/\(Fmt.tok(o.fairness?.sixHourPrompt)) in",
        "Token 累计 \(Fmt.tok(o.tokens?.total))（入 \(Fmt.tok(o.tokens?.prompt)) · 出 \(Fmt.tok(o.tokens?.completion))）",
        "剩余 \(Fmt.left(o.remainingMs, expired: o.expired == true)) 至 \(Fmt.date(o.expiresAt))",
        st.bad ? "到期 \(Fmt.date(o.expiresAt)) · 详见 https://monk.party/account/" : ""
    ].filter { !$0.isEmpty }.joined(separator: " | ")
}

// MARK: - 状态栏显示模式与 Attributed 渲染

enum StatusDisplayMode: String, CaseIterable {
    case detailed = "detailed"  // 详细: 额度 (百分比) · 剩余天数
    case compact = "compact"    // 紧凑: 仅今日内部计量
    case iconOnly = "iconOnly"  // 仅图标: 极简

    var title: String {
        switch self {
        case .detailed: return "详细模式 (额度 + 百分比 + 剩余天数)"
        case .compact: return "紧凑模式 (仅今日内部计量)"
        case .iconOnly: return "仅图标模式 (极简)"
        }
    }
}

func makeStatusAttributedTitle(
    cost: Double?,
    limit: Double?,
    remainingMs: Double?,
    isBad: Bool,
    mode: StatusDisplayMode,
    rawText: String? = nil
) -> NSAttributedString {
    if let raw = rawText {
        return NSAttributedString(string: " " + raw, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    let result = NSMutableAttributedString()
    guard mode != .iconOnly else {
        if isBad {
            let warn = NSAttributedString(string: " ⚠︎", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: NSColor.systemOrange
            ])
            result.append(warn)
        }
        return result
    }

    let c = cost ?? 0
    let costStr = c < 10 ? String(format: "¥%.2f", c) : String(format: "¥%.1f", c)
    let primary = NSAttributedString(string: " " + costStr, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: isBad ? NSColor.systemRed : NSColor.labelColor
    ])
    result.append(primary)

    if mode == .detailed {
        let lim = max(0.01, limit ?? 30.0)
        let pct = Int(min(100, max(0, (c / lim) * 100)))
        let pctAttr = NSAttributedString(string: " (\(pct)%)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: pct > 80 ? NSColor.systemRed : NSColor.secondaryLabelColor
        ])
        result.append(pctAttr)

        if let ms = remainingMs, ms > 0 {
            let days = Int(ms / 1000) / 86400
            let daysAttr = NSAttributedString(string: " · \(days)d", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            result.append(daysAttr)
        }
    }

    if isBad {
        let warn = NSAttributedString(string: " ⚠︎", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
            .foregroundColor: NSColor.systemOrange
        ])
        result.append(warn)
    }

    return result
}

// MARK: - 系统适配与信息 (macOS 13+ / macOS Tahoe 27+)

enum SystemInfo {
    static var macOSName: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        switch v.majorVersion {
        case 26, 27:
            return "macOS Tahoe (\(v.majorVersion).\(v.minorVersion))"
        case 15:
            return "macOS Sequoia (15.\(v.minorVersion))"
        case 14:
            return "macOS Sonoma (14.\(v.minorVersion))"
        case 13:
            return "macOS Ventura (13.\(v.minorVersion))"
        default:
            if v.majorVersion >= 26 {
                return "macOS Tahoe (\(v.majorVersion).\(v.minorVersion))"
            }
            return "macOS (\(v.majorVersion).\(v.minorVersion))"
        }
    }
}

// MARK: - 菜单栏 App

final class Agent: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let fetcher = Fetcher()
    var order: Order?
    var note: String?
    var autoRefresh = false
    var displayMode: StatusDisplayMode = .detailed
    var timer: Timer?

    func start() {
        NSApp.setActivationPolicy(.accessory)
        displayMode = StatusDisplayMode(rawValue: UserDefaults.standard.string(forKey: "monkStatusDisplayMode") ?? "") ?? .detailed
        item.autosaveName = "party.monk.usage.statusItem"
        item.button?.image = Visuals.makeMenuIcon()
        item.button?.imagePosition = .imageLeft
        item.menu = NSMenu(title: "monk")
        item.menu?.delegate = self
        setAttributedTitle(NSAttributedString(string: " …", attributes: [.font: NSFont.systemFont(ofSize: 11.5)]), tip: "monk 用量")
        refreshIfNeeded()
        // 首次运行（或配置不可用）直接弹设置窗，避免被迫找文件
        if Cfg.load() == nil {
            DispatchQueue.main.async { [weak self] in self?.doSettings() }
        }
    }

    func setAttributedTitle(_ attr: NSAttributedString, tip: String) {
        item.button?.attributedTitle = attr
        item.button?.toolTip = tip
    }

    func refreshIfNeeded() {
        guard let cfg = Cfg.load() else {
            order = nil
            note = "未配置：点击下方「设置账号…」填邮箱与订单号"
            render()
            return
        }
        fetcher.lookup(cfg) { [weak self] o, e in
            guard let self else { return }
            self.order = o ?? self.order
            self.note = e
            self.render()
        }
    }

    func render() {
        if let o = order {
            let st = state(o)
            let expiring = isExpiringSoon(o)
            setAttributedTitle(
                makeStatusAttributedTitle(cost: o.dailyCost, limit: o.dailyLimit, remainingMs: o.remainingMs, isBad: st.bad || expiring, mode: displayMode),
                tip: summaryLine(o) + (expiring ? " | ⚠️ 有效期不足 3 天，建议续费" : "")
            )
        } else if Cfg.load() == nil {
            setAttributedTitle(
                makeStatusAttributedTitle(cost: nil, limit: nil, remainingMs: nil, isBad: false, mode: displayMode, rawText: "未配置"),
                tip: "点击配置邮箱与订单号"
            )
        } else {
            setAttributedTitle(
                makeStatusAttributedTitle(cost: nil, limit: nil, remainingMs: nil, isBad: true, mode: displayMode, rawText: "查询失败"),
                tip: note ?? ""
            )
        }
        if item.menu?.items.isEmpty == false { item.menu?.delegate?.menuNeedsUpdate?(item.menu!) }
    }

    func setDisplayMode(_ mode: StatusDisplayMode) {
        self.displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "monkStatusDisplayMode")
        render()
        item.menu?.delegate?.menuNeedsUpdate?(item.menu!)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 当有效期不足 3 天或已到期时，置顶醒目引导续费新套餐
        if let o = order, isExpiringSoon(o) {
            let daysLeft = Fmt.left(o.remainingMs, expired: o.expired == true)
            let title = o.expired == true ? "⚠️ 订阅已到期 · 立即续订新套餐 ↗" : "🔥 订阅即将到期 (剩余 \(daysLeft)) · 立即续订 ↗"
            let renewItem = NSMenuItem(title: title, action: #selector(doOpenPricing), keyEquivalent: "")
            renewItem.target = self
            menu.addItem(renewItem)
            menu.addItem(.separator())
        }

        if let o = order { addOrderItems(to: menu, o) }
        if let note { menu.addItem(info("⚠︎ " + note, multiline: true)) }
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新", action: #selector(doRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        // 状态栏显示模式子菜单
        let styleItem = NSMenuItem(title: "状态栏显示样式", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu(title: "状态栏显示样式")

        let modeDetailed = NSMenuItem(title: "详细模式 (额度 + 百分比 + 剩余天数)", action: #selector(selectModeDetailed), keyEquivalent: "")
        modeDetailed.target = self
        modeDetailed.state = displayMode == .detailed ? .on : .off
        styleSubmenu.addItem(modeDetailed)

        let modeCompact = NSMenuItem(title: "紧凑模式 (仅今日内部计量)", action: #selector(selectModeCompact), keyEquivalent: "")
        modeCompact.target = self
        modeCompact.state = displayMode == .compact ? .on : .off
        styleSubmenu.addItem(modeCompact)

        let modeIconOnly = NSMenuItem(title: "仅图标模式 (极简，有异常才提示)", action: #selector(selectModeIconOnly), keyEquivalent: "")
        modeIconOnly.target = self
        modeIconOnly.state = displayMode == .iconOnly ? .on : .off
        styleSubmenu.addItem(modeIconOnly)

        styleItem.submenu = styleSubmenu
        menu.addItem(styleItem)

        let auto = NSMenuItem(title: "自动刷新（5 分钟）", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = autoRefresh ? .on : .off
        auto.indentationLevel = 1
        menu.addItem(auto)
        if autoRefresh {
            menu.addItem(info("官方按查询计一次今日用量，已放缓为 5 分钟一次", multiline: true))
        }

        menu.addItem(.separator())
        let acct = NSMenuItem(title: "打开账户页", action: #selector(doAccount), keyEquivalent: "a")
        acct.keyEquivalentModifierMask = [.command, .shift]
        acct.target = self
        menu.addItem(acct)

        // 推荐搭配的 Monk-Pi Coding Agent 工具
        let monkPiItem = NSMenuItem(title: "⚡️ 推荐 Agent 工具：Monk-Pi 终端助手 ↗", action: #selector(doOpenMonkPi), keyEquivalent: "")
        monkPiItem.target = self
        menu.addItem(monkPiItem)

        let conf = NSMenuItem(title: "设置账号…", action: #selector(doSettings), keyEquivalent: ",")
        conf.target = self
        menu.addItem(conf)
        let raw = NSMenuItem(title: "打开配置文件", action: #selector(doConfig), keyEquivalent: "")
        raw.target = self
        menu.addItem(raw)
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func addOrderItems(to menu: NSMenu, _ o: Order) {
        let st = state(o)
        menu.addItem(info("状态　\(st.label)"))
        menu.addItem(info("Key　　\(masked(o.apiKey))　（点击复制）", action: #selector(doCopyKey), target: self))
        menu.addItem(info("剩余　\(Fmt.left(o.remainingMs, expired: o.expired == true))　到期 \(Fmt.date(o.expiresAt))"))
        menu.addItem(info("今日　\(Fmt.bar(o.dailyCost, o.dailyLimit)) \(Fmt.money(o.dailyCost)) / \(Fmt.money(o.dailyLimit))　保险丝，UTC 00:00 清零"))
        menu.addItem(info("Token　累计 \(Fmt.tok(o.tokens?.total))　入 \(Fmt.tok(o.tokens?.prompt)) · 出 \(Fmt.tok(o.tokens?.completion))"))

        if let r = o.rateLimit, let fair = o.fairness {
            menu.addItem(.separator())
            menu.addItem(info("1 小时　\(Fmt.bar(r.hour?.w, fair.hourMax)) \(Fmt.num(r.hour?.w))/\(Fmt.num(fair.hourMax)) 次 · \(Fmt.tok(r.hour?.pin))/\(Fmt.tok(fair.hourPrompt)) in"))
            menu.addItem(info("6 小时　\(Fmt.bar(r.six?.w, fair.sixHourMax)) \(Fmt.num(r.six?.w))/\(Fmt.num(fair.sixHourMax)) 次 · \(Fmt.tok(r.six?.pin))/\(Fmt.tok(fair.sixHourPrompt)) in"))
            menu.addItem(info("并发　　每 Key \(Fmt.num(fair.inflightPerKey)) 路 · 全站 \(Fmt.num(fair.inflightGlobal)) 路 · 桶 \(Fmt.num(fair.burstCapacity))/补 \(Fmt.num(fair.burstRefillPerMin)) 每分钟"))
        }
        if let cd = o.cooldownUntil, Fmt.parse(cd)?.timeIntervalSinceNow ?? -1 > 0 {
            menu.addItem(info("冷却　　至 \(Fmt.date(cd))（北京时间）"))
        }
    }

    func masked(_ key: String?) -> String {
        guard let key, key.count > 10 else { return key ?? "—" }
        return key.prefix(6) + "…" + key.suffix(4)
    }

    @discardableResult
    func info(_ text: String, multiline: Bool = false,
              action: Selector? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: text, action: action, keyEquivalent: "")
        if let action, let target {
            it.action = action
            it.target = target
        } else {
            it.isEnabled = false
        }
        if multiline {
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byWordWrapping
            p.maximumLineHeight = 15
            it.attributedTitle = NSAttributedString(string: text, attributes: [
                .paragraphStyle: p,
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        return it
    }

    @objc func doRefresh() { refreshIfNeeded() }

    @objc func doOpenPricing() {
        NSWorkspace.shared.open(URL(string: "https://monk.party/")!)
    }

    @objc func doOpenMonkPi() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yaoleifly/monk-pi")!)
    }

    @objc func selectModeDetailed() { setDisplayMode(.detailed) }
    @objc func selectModeCompact() { setDisplayMode(.compact) }
    @objc func selectModeIconOnly() { setDisplayMode(.iconOnly) }

    @objc func toggleAuto() {
        autoRefresh.toggle()
        UserDefaults.standard.set(autoRefresh, forKey: "monkAutoRefresh")
        timer?.invalidate()
        if autoRefresh {
            // 官方明示「一次查询计算一次今日用量」，故下限 300s，不做秒表。
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.refreshIfNeeded()
            }
            refreshIfNeeded()
        }
        item.menu?.delegate?.menuNeedsUpdate?(item.menu!)
    }

    @objc func doAccount() { NSWorkspace.shared.open(Cfg.accountPage) }

    @objc func doSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show(agent: self)
    }

    @objc func doConfig() {
        Cfg.ensureTemplateWritten()
        NSWorkspace.shared.open(Cfg.url)
    }

    @objc func doCopyKey() {
        guard let key = order?.apiKey, !key.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(key, forType: .string)
        note = "API Key 已复制到剪贴板"
        render()
    }

    func restoreAuto() {
        autoRefresh = UserDefaults.standard.bool(forKey: "monkAutoRefresh")
        guard autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
    }
}

// MARK: - Apple HIG 极致体验设置与实时监控中心 (SwiftUI + AppKit)

final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var tradeNo: String = ""
    @Published var autoRefresh: Bool = false
    @Published var statusDisplayMode: StatusDisplayMode = .detailed
    @Published var validationError: String? = nil
    @Published var saveSuccess: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var copiedKey: Bool = false
    @Published var copiedBaseURL: Bool = false

    weak var agent: Agent?

    func loadFromCurrent(agent: Agent) {
        self.agent = agent
        let cfg = Cfg.load()
        self.email = cfg?.email ?? ""
        self.tradeNo = cfg?.tradeNo ?? ""
        self.autoRefresh = agent.autoRefresh
        self.statusDisplayMode = agent.displayMode
        self.validationError = nil
        self.saveSuccess = false
        self.copiedKey = false
        self.copiedBaseURL = false
    }

    func copyKey(_ key: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(key, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { copiedKey = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.copiedKey = false }
        }
    }

    func copyBaseURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("https://monk.party/v1", forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { copiedBaseURL = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.copiedBaseURL = false }
        }
    }

    @Published var copiedMonkPiNpx: Bool = false
    @Published var copiedMonkPiBrew: Bool = false

    func copyMonkPiNpx() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("npx monk-pi", forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { copiedMonkPiNpx = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.copiedMonkPiNpx = false }
        }
    }

    func copyMonkPiBrew() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("brew install yaoleifly/tap/monk-pi", forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { copiedMonkPiBrew = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.copiedMonkPiBrew = false }
        }
    }

    func openMonkPiGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yaoleifly/monk-pi")!)
    }

    func openPricing() {
        NSWorkspace.shared.open(URL(string: "https://monk.party/")!)
    }

    func refreshNow() {
        guard let agent = agent, Cfg.load() != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = true }
        agent.refreshIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.isRefreshing = false }
        }
    }

    func saveAndRefresh() {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = tradeNo.trimmingCharacters(in: .whitespacesAndNewlines)

        if e.isEmpty || !e.contains("@") {
            validationError = "请填写有效的下单邮箱地址"
            saveSuccess = false
            return
        }
        if t.isEmpty {
            validationError = "请填写购买订单号（形如 MK...）"
            saveSuccess = false
            return
        }

        validationError = nil
        Cfg.save(Config(email: e, tradeNo: t))

        if let agent = agent {
            if agent.autoRefresh != autoRefresh {
                agent.autoRefresh = autoRefresh
                UserDefaults.standard.set(autoRefresh, forKey: "monkAutoRefresh")
                agent.timer?.invalidate()
                if autoRefresh {
                    agent.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak agent] _ in
                        agent?.refreshIfNeeded()
                    }
                }
            }
            if agent.displayMode != statusDisplayMode {
                agent.setDisplayMode(statusDisplayMode)
            }
            withAnimation { isRefreshing = true }
            agent.note = nil
            agent.refreshIfNeeded()
        }

        withAnimation(.spring()) {
            saveSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation {
                self?.saveSuccess = false
                self?.isRefreshing = false
            }
        }
    }
}

// MARK: - 精致视觉卡片与仪表组件

struct MetricCard<Content: View>: View {
    var title: String
    var icon: String
    var iconColor: Color
    var badge: String? = nil
    var badgeColor: Color = .green
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }
            }
            content
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct GaugeBar: View {
    var value: Double
    var total: Double
    var tintColors: [Color] = [Visuals.flameOrange, Visuals.flameGold]

    var pct: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, value / total))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 7)
                Capsule()
                    .fill(LinearGradient(colors: tintColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(7, geo.size.width * pct), height: 7)
            }
        }
        .frame(height: 7)
    }
}

struct TokenSegmentBar: View {
    var prompt: Double
    var completion: Double

    var total: Double { max(1, prompt + completion) }
    var promptPct: Double { prompt / total }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * promptPct))
                    Capsule()
                        .fill(LinearGradient(colors: [Visuals.flameOrange, Visuals.flameGold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * (1.0 - promptPct)))
                }
            }
            .frame(height: 7)

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text("输入 Prompt: \(Fmt.tok(prompt)) (\(String(format: "%.1f", promptPct * 100))%)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Visuals.flameOrange).frame(width: 7, height: 7)
                    Text("输出 Output: \(Fmt.tok(completion)) (\(String(format: "%.1f", (1.0 - promptPct) * 100))%)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RateLimitRow: View {
    var title: String
    var current: Double
    var maxVal: Double
    var isToken: Bool = false

    var pct: Double { maxVal > 0 ? min(1.0, current / maxVal) : 0 }
    var barColor: Color {
        if pct > 0.85 { return .red }
        if pct > 0.6 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if isToken {
                    Text("\(Fmt.tok(current)) / \(Fmt.tok(maxVal))")
                        .font(.caption2.monospacedDigit().weight(.medium))
                } else {
                    Text("\(Fmt.num(current)) / \(Fmt.num(maxVal)) 次")
                        .font(.caption2.monospacedDigit().weight(.medium))
                }
            }
            GaugeBar(value: current, total: maxVal, tintColors: [barColor, barColor.opacity(0.8)])
        }
    }
}

// MARK: - 主设置面板 (SettingsView)

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部 Header (包含品牌图标、状态徽章与即时刷新按钮)
            headerView
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            // 2. 主体可滚动仪表盘 (ScrollView)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if let o = model.agent?.order {
                        // 有效期不足 3 天或已过期时，置顶显示醒目续费卡片
                        if isExpiringSoon(o) {
                            renewalBanner(o)
                        }
                        // 订单已加载：展示全套 Bento Grid 仪表盘
                        liveDashboard(o)
                    } else {
                        // 未加载或未配置：引导卡片
                        unconfiguredCard
                    }

                    // 推荐搭配的 Monk-Pi Coding Agent 工具卡片
                    monkPiRecommendationCard

                    // 凭据配置卡片
                    credentialsCard

                    // 通用偏好卡片
                    preferencesCard
                }
                .padding(20)
            }

            Divider()

            // 3. 底部标准操作工具栏
            bottomActionBar
        }
        .frame(width: 560, height: 660)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            Image(nsImage: Visuals.appIconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Monk 实时监控与设置")
                        .font(.system(size: 16, weight: .bold))

                    statusBadge
                }

                HStack(spacing: 6) {
                    Text("OpenAI 兼容融合网关 (monk / monk-fast / monk-coding)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(SystemInfo.macOSName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 立即刷新按钮
            Button {
                model.refreshNow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(model.isRefreshing ? .degrees(360) : .zero)
                        .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
                    Text(model.isRefreshing ? "正在同步…" : "立即刷新")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing || Cfg.load() == nil)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let o = model.agent?.order {
            let st = state(o)
            Text(st.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(st.bad ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                .foregroundStyle(st.bad ? Color.red : Color.green)
                .clipShape(Capsule())
        } else if Cfg.load() == nil {
            Text("未配置")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(Color.orange)
                .clipShape(Capsule())
        } else {
            Text("连接异常")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color.red)
                .clipShape(Capsule())
        }
    }

    // MARK: - 实时状态与配额 Bento Grid
    private func liveDashboard(_ o: Order) -> some View {
        VStack(spacing: 14) {
            // Row 1: 双列核心指标卡片 (今日内部计量 + 订阅有效期限)
            HStack(spacing: 14) {
                // 卡片 1: 今日内部计量 (保险丝)
                let cost = o.dailyCost ?? 0
                let limit = max(0.01, o.dailyLimit ?? 30.0)
                let pct = Int(min(100, max(0, (cost / limit) * 100)))
                let remainCost = max(0, limit - cost)

                MetricCard(title: "今日内部计量", icon: "flame.fill", iconColor: Visuals.flameOrange, badge: "熔断保险丝", badgeColor: Visuals.flameOrange) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.money(cost))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(pct > 80 ? .red : .primary)
                            Text("/ \(Fmt.money(limit))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(pct)%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(pct > 80 ? .red : Visuals.flameOrange)
                        }

                        GaugeBar(value: cost, total: limit, tintColors: pct > 80 ? [.red, .orange] : [Visuals.flameOrange, Visuals.flameGold])

                        HStack {
                            Text("剩余安全额度: \(Fmt.money(remainCost))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("UTC 00:00 清零")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // 卡片 2: 订阅有效期与健康度
                let (days, hours) = parseDaysHours(o.remainingMs)
                let st = state(o)

                MetricCard(title: "订阅有效期", icon: "calendar.badge.clock", iconColor: .blue, badge: st.label, badgeColor: st.bad ? .red : .green) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if o.expired == true {
                                Text("已到期")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(days)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                Text("天")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text("\(hours)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text("小时")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Text("到期时间: \(Fmt.date(o.expiresAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(o.status == "paid" ? "月卡正常生效中" : "订单状态: \(o.status ?? "未知")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let cd = o.cooldownUntil, Fmt.parse(cd)?.timeIntervalSinceNow ?? -1 > 0 {
                                Text("冷却至 \(Fmt.date(cd))")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            // Row 2: Token 消耗分流卡片
            if let tok = o.tokens, let total = tok.total, total > 0 {
                MetricCard(title: "累计 Token 吞吐与分流", icon: "gauge.with.dots.needle.bottom.50percent", iconColor: .indigo, badge: "总计 \(Fmt.tok(total))", badgeColor: .indigo) {
                    TokenSegmentBar(prompt: tok.prompt ?? 0, completion: tok.completion ?? 0)
                }
            }

            // Row 3: 双窗口限流与加权调度面板
            if let r = o.rateLimit, let fair = o.fairness {
                MetricCard(title: "限流保护与公平调度", icon: "shield.lefthalf.filled", iconColor: .teal, badge: "防 429 机制", badgeColor: .teal) {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 18) {
                            // 1 小时窗口
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("1 小时滑动窗口")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                }
                                RateLimitRow(title: "加权请求", current: r.hour?.w ?? 0, maxVal: fair.hourMax ?? 60, isToken: false)
                                RateLimitRow(title: "输入 Token", current: r.hour?.pin ?? 0, maxVal: fair.hourPrompt ?? 30_000_000, isToken: true)
                            }

                            Divider().frame(height: 70)

                            // 6 小时窗口
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("6 小时滑动窗口")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                }
                                RateLimitRow(title: "加权请求", current: r.six?.w ?? 0, maxVal: fair.sixHourMax ?? 200, isToken: false)
                                RateLimitRow(title: "输入 Token", current: r.six?.pin ?? 0, maxVal: fair.sixHourPrompt ?? 120_000_000, isToken: true)
                            }
                        }

                        // 并发与突发保护胶囊
                        HStack(spacing: 8) {
                            ruleCapsule(icon: "bolt.fill", title: "并发限制", detail: "单Key \(Fmt.num(fair.inflightPerKey))路 · 全站 \(Fmt.num(fair.inflightGlobal))路")
                            ruleCapsule(icon: "archivebox.fill", title: "令牌桶突发", detail: "容量 \(Fmt.num(fair.burstCapacity)) · 补 \(Fmt.num(fair.burstRefillPerMin))次/分")
                            ruleCapsule(icon: "exclamationmark.shield.fill", title: "429 罚则", detail: "连续 \(Fmt.num(fair.penalty429PerMin))次罚 \(Fmt.num(fair.penaltyMinutes))分")
                        }
                    }
                }
            }

            // Row 4: 开发者集成与 API Key 卡片
            if let key = o.apiKey, !key.isEmpty {
                MetricCard(title: "API Key 与模型集成", icon: "terminal.fill", iconColor: .purple) {
                    VStack(spacing: 8) {
                        // API Key 行
                        HStack {
                            Label("API Key", systemImage: "key.fill")
                                .font(.caption.weight(.semibold))
                                .frame(width: 80, alignment: .leading)
                            Text(masked(key))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Spacer()
                            Button {
                                model.copyKey(key)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: model.copiedKey ? "checkmark" : "doc.on.doc")
                                    Text(model.copiedKey ? "已复制" : "复制 Key")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        // Base URL 行
                        HStack {
                            Label("Base URL", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .frame(width: 80, alignment: .leading)
                            Text("https://monk.party/v1")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Spacer()
                            Button {
                                model.copyBaseURL()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: model.copiedBaseURL ? "checkmark" : "doc.on.doc")
                                    Text(model.copiedBaseURL ? "已复制" : "复制 URL")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        // 模型支持 Tags
                        HStack(spacing: 8) {
                            Text("可用模型:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            modelTag(name: "monk", desc: "质量优先·默认")
                            modelTag(name: "monk-fast", desc: "极速日常")
                            modelTag(name: "monk-coding", desc: "编程专用")
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func ruleCapsule(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Visuals.flameOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func modelTag(name: String, desc: String) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
            Text("(\(desc))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 到期续费引导横幅
    @ViewBuilder
    private func renewalBanner(_ o: Order) -> some View {
        let daysLeft = Fmt.left(o.remainingMs, expired: o.expired == true)
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 22))
                .foregroundStyle(Visuals.flameOrange)
                .frame(width: 40, height: 40)
                .background(Visuals.flameOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(o.expired == true ? "Monk 套餐已到期" : "Monk 套餐即将到期")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Visuals.flameOrange)

                    Text("剩余 \(daysLeft)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Visuals.flameOrange.opacity(0.15))
                        .foregroundStyle(Visuals.flameOrange)
                        .clipShape(Capsule())
                }

                Text(o.expired == true
                    ? "您的月卡权限已到期，无法继续调用。请续订新套餐以立即恢复模型调用服务。"
                    : "当前套餐有效期不足 3 天（到期时间 \(Fmt.date(o.expiresAt))）。为保证日常开发与 Coding Agent 服务不中断，建议提前续费。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.openPricing()
            } label: {
                HStack(spacing: 4) {
                    Text("立即续订新套餐")
                    Image(systemName: "arrow.up.forward.app")
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Visuals.flameOrange)
        }
        .padding(12)
        .background(Visuals.flameOrange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Visuals.flameOrange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - 推荐搭配 Monk-Pi 工具卡片
    private var monkPiRecommendationCard: some View {
        MetricCard(title: "推荐搭配 · Monk × Pi 终端 Coding Agent", icon: "sparkles", iconColor: Visuals.flameOrange, badge: "官方推荐 · 零配置", badgeColor: Visuals.flameOrange) {
            VStack(alignment: .leading, spacing: 10) {
                Text("将 Monk 的 OpenAI 兼容融合模型（100 万上下文 / Agent 原生调优）与极速终端 Agent 深度结合。无需手写繁琐配置，预置 `monk-coding` 专属模型优化。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    // 命令 1: npx monk-pi
                    HStack(spacing: 6) {
                        Text("npx monk-pi")
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                        Spacer()
                        Button {
                            model.copyMonkPiNpx()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: model.copiedMonkPiNpx ? "checkmark" : "doc.on.doc")
                                Text(model.copiedMonkPiNpx ? "已复制" : "免安装即跑")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Visuals.flameOrange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    // 命令 2: brew install yaoleifly/tap/monk-pi
                    HStack(spacing: 6) {
                        Text("brew install ...")
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                        Spacer()
                        Button {
                            model.copyMonkPiBrew()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: model.copiedMonkPiBrew ? "checkmark" : "doc.on.doc")
                                Text(model.copiedMonkPiBrew ? "已复制" : "Homebrew")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Visuals.flameOrange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                HStack {
                    Spacer()
                    Button {
                        model.openMonkPiGitHub()
                    } label: {
                        HStack(spacing: 4) {
                            Text("在 GitHub 查看 yaoleifly/monk-pi")
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - 未配置指引卡片
    private var unconfiguredCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 38))
                .foregroundStyle(Visuals.flameOrange)
                .padding(.top, 8)

            Text("尚未连接 Monk 账户")
                .font(.system(size: 15, weight: .bold))

            Text("请在下方输入你下单时填写的邮箱与订单号（形如 MK...），点击「保存并刷新」，即可自动调取实时内部计量、健康度与 API Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button {
                NSWorkspace.shared.open(Cfg.accountPage)
            } label: {
                Label("前往 monk.party 官网查看或购买", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.link)
            .font(.caption.weight(.medium))
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - 账号凭据配置卡片
    private var credentialsCard: some View {
        MetricCard(title: "账号凭据设置", icon: "person.crop.circle.badge.checkmark", iconColor: .primary) {
            VStack(spacing: 10) {
                HStack {
                    Label("下单邮箱", systemImage: "envelope")
                        .font(.caption.weight(.semibold))
                        .frame(width: 80, alignment: .leading)
                    TextField("如 your@email.com", text: $model.email)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Label("订单号", systemImage: "number")
                        .font(.caption.weight(.semibold))
                        .frame(width: 80, alignment: .leading)
                    TextField("形如 MK...", text: $model.tradeNo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                if let err = model.validationError {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(err)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.shield")
                        Text("凭据仅保存在本机 Application Support，绝不上报第三方。")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 通用偏好卡片
    private var preferencesCard: some View {
        MetricCard(title: "偏好与轮询", icon: "gearshape", iconColor: .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("状态栏显示样式")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Picker("", selection: $model.statusDisplayMode) {
                        ForEach(StatusDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 250)
                }

                Divider()

                Toggle("开启后台自动刷新 (5分钟安全间隔)", isOn: $model.autoRefresh)
                    .font(.caption.weight(.medium))

                Text("根据 monk.party 官方说明，「一次查询计算一次今日用量」，为保护您的每日额度，轮询间隔已锁定为 5 分钟安全下限。日常建议手动按 ⌘R 刷新。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 底部操作栏
    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            Button {
                NSWorkspace.shared.open(Cfg.accountPage)
            } label: {
                Label("官方网站", systemImage: "safari")
            }
            .buttonStyle(.link)
            .font(.callout)

            Button {
                NSWorkspace.shared.open(Cfg.url)
            } label: {
                Label("打开配置文件", systemImage: "doc.text")
            }
            .buttonStyle(.link)
            .font(.callout)

            Spacer()

            if model.saveSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("已保存并刷新")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .transition(.opacity)
            }

            Button("关闭") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Button("保存并刷新") {
                model.saveAndRefresh()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Visuals.flameOrange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func masked(_ key: String) -> String {
        guard key.count > 12 else { return key }
        return key.prefix(7) + "••••••••" + key.suffix(4)
    }

    private func parseDaysHours(_ ms: Double?) -> (days: Int, hours: Int) {
        guard let ms = ms, ms > 0 else { return (0, 0) }
        let s = Int(ms / 1000)
        let d = s / 86400
        let h = (s % 86400) / 3600
        return (d, h)
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var model = SettingsViewModel()

    func show(agent: Agent) {
        model.loadFromCurrent(agent: agent)

        if window == nil {
            let view = SettingsView(model: model) { [weak self] in
                self?.window?.close()
            }
            let host = NSHostingView(rootView: view)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Monk 设置"
            win.minSize = NSSize(width: 520, height: 580)
            win.contentView = host
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            self.window = win
        } else {
            let view = SettingsView(model: model) { [weak self] in
                self?.window?.close()
            }
            window?.contentView = NSHostingView(rootView: view)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - CLI

func cliExit(_ cfg: Config?, wantJSON: Bool) -> Int32 {
    guard let cfg else {
        FileHandle.standardError.write("未配置：\(Cfg.url.path)\n".data(using: .utf8)!)
        return 2
    }
    let sem = DispatchSemaphore(value: 0)
    var code: Int32 = 1
    var req = URLRequest(url: Cfg.endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": cfg.email, "tradeNo": cfg.tradeNo])
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }
        if let err {
            FileHandle.standardError.write("网络错误：\(err.localizedDescription)\n".data(using: .utf8)!)
            return
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = data ?? Data()
        if wantJSON {
            FileHandle.standardOutput.write(body)
            FileHandle.standardOutput.write(Data("\n".utf8))
            code = (200...299).contains(status) ? 0 : 1
            return
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: body), let o = root.order else {
            let msg = (try? JSONDecoder().decode(Root.self, from: body))?.error ?? "HTTP \(status)"
            FileHandle.standardError.write("monk 查询失败：\(msg)\n".data(using: .utf8)!)
            code = 1
            return
        }
        print(summaryLine(o))
        code = 0
    }.resume()
    sem.wait()
    return code
}

// MARK: - 自检

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("SELF-CHECK FAILED: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func expect(_ cond: Bool, _ msg: String) {
    if !cond { fail(msg) }
}

func selfCheck() {
    let fixture = """
    {"success":true,"order":{
      "apiKey":"monk-abcdefgh1234","tradeNo":"MK123","status":"paid",
      "expiresAt":"2026-09-28T14:26:24.139Z","remainingMs":1094400000,
      "expired":false,"soon":false,"keyActive":true,
      "dailyCost":0.4,"dailyLimit":30.0,
      "tokens":{"prompt":1200000,"completion":30000,"total":1230000},
      "fairness":{"hourMax":60,"hourPrompt":30000000,"sixHourMax":200,"sixHourPrompt":120000000,
                  "inflightPerKey":2,"inflightGlobal":8,"burstCapacity":20,"burstRefillPerMin":8,
                  "penalty429PerMin":20,"penaltyMinutes":15},
      "rateLimit":{"limited":false,"hour":{"w":3,"pin":120000},"six":{"w":12,"pin":1400000}},
      "cooldownUntil":"2026-10-01T00:00:00Z"
    }}
    """
    let root: Root
    do { root = try JSONDecoder().decode(Root.self, from: Data(fixture.utf8)) }
    catch { fail("decode: \(error)") }
    guard let o = root.order else { fail("no order") }

    expect(o.apiKey == "monk-abcdefgh1234", "apiKey")
    expect(o.dailyCost == 0.4 && o.dailyLimit == 30, "daily")
    expect(o.rateLimit?.hour?.w == 3 && o.rateLimit?.six?.pin == 1_400_000, "rate windows")
    expect(o.fairness?.inflightGlobal == 8, "fairness")
    expect(o.remainingMs == 1_094_400_000, "remainingMs")
    // 缺字段容错（服务端不返 fairness 时不应整体解码失败）
    let sparse = try! JSONDecoder().decode(Root.self, from: Data(#"{"success":true,"order":{"apiKey":"k"}}"#.utf8))
    expect(sparse.order?.fairness == nil, "sparse order")
    // 带/不带小数秒的 ISO8601 都要能解
    expect(Fmt.parse("2026-10-01T00:00:00Z") != nil, "iso plain")
    expect(Fmt.parse("2026-09-28T14:26:24.139Z") != nil, "iso fractional")
    expect(Fmt.parse("garbage") == nil, "iso garbage")

    expect(Fmt.money(0.4) == "¥0.40", "money small")
    expect(Fmt.money(12.34) == "¥12.3", "money big")
    expect(Fmt.tok(1_230_000) == "1.23M", "tok M")
    expect(Fmt.tok(2_000) == "2k", "tok k")
    expect(Fmt.num(60) == "60", "num int")
    expect(Fmt.num(2.5) == "2.5", "num frac")
    expect(Fmt.bar(15, 30) == String(repeating: "▰", count: 5) + String(repeating: "▱", count: 5), "bar half")
    expect(Fmt.bar(99, 30) == String(repeating: "▰", count: 10), "bar overflow")
    expect(Fmt.bar(nil, 30) == "—", "bar nil")
    expect(Fmt.left(1_094_400_000, expired: false) == "约 12 天 16 小时", "left days")
    expect(Fmt.left(0, expired: true) == "已到期", "left expired")
    expect(Fmt.date("2026-09-28T14:26:24.139Z", zone: "Asia/Shanghai") == "2026-09-28 22:26", "date zone")

    // 冷却时间在未来 → 冷却中；过去 → 可调用
    let cool = Order(apiKey: "k", tradeNo: nil, status: "paid", createdAt: nil, paidAt: nil,
                     expiresAt: nil, remainingMs: 1, expired: false, soon: false, keyActive: true,
                     dailyCost: 0, dailyLimit: 30, tokens: nil, fairness: nil,
                     rateLimit: RateLimit(limited: false, retryAt: nil, hour: nil, six: nil),
                     cooldownUntil: "2999-01-01T00:00:00Z")
    expect(state(cool).label.hasPrefix("冷却中"), "state cooling")
    var paid = cool
    paid.cooldownUntil = "2000-01-01T00:00:00Z"
    expect(state(paid).label == "可调用", "state ok")
    paid.rateLimit?.limited = true
    expect(state(paid).label.hasPrefix("限流中"), "state limited")
    paid.expired = true
    expect(state(paid).label == "已停用", "state expired")
    expect(summaryLine(o).contains("今日 ¥0.40/¥30.0"), "summary daily")
    expect(summaryLine(o).contains("1h 3/60 次"), "summary hour window")
    expect(summaryLine(o).contains("约 12 天 16 小时"), "summary remaining")

    // 状态栏三种显示模式自检
    let attrDet = makeStatusAttributedTitle(cost: 0.40, limit: 30.0, remainingMs: 1094400000, isBad: false, mode: .detailed)
    expect(attrDet.string.contains("¥0.40"), "status title cost")
    expect(attrDet.string.contains("(1%)"), "status title pct")
    expect(attrDet.string.contains("· 12d"), "status title days")

    let attrComp = makeStatusAttributedTitle(cost: 0.40, limit: 30.0, remainingMs: 1094400000, isBad: false, mode: .compact)
    expect(attrComp.string == " ¥0.40", "status title compact")

    let attrIcon = makeStatusAttributedTitle(cost: 0.40, limit: 30.0, remainingMs: 1094400000, isBad: false, mode: .iconOnly)
    expect(attrIcon.string.isEmpty, "status title iconOnly normal")

    let attrWarn = makeStatusAttributedTitle(cost: 0.40, limit: 30.0, remainingMs: 1094400000, isBad: true, mode: .iconOnly)
    expect(attrWarn.string.contains("⚠︎"), "status title iconOnly warn")

    // 有效期不足 3 天判定自检
    expect(isExpiringSoon(cool) == true, "expiring soon cool (1ms)")
    var longOrder = cool
    longOrder.remainingMs = 10 * 86400 * 1000 // 10 days
    expect(isExpiringSoon(longOrder) == false, "expiring soon 10d")
    longOrder.remainingMs = 2 * 86400 * 1000 // 2 days
    expect(isExpiringSoon(longOrder) == true, "expiring soon 2d")

    expect(!SystemInfo.macOSName.isEmpty, "macOSName non-empty")

    print("selfcheck ok")
}

// MARK: - 入口

let args = CommandLine.arguments

if args.contains("--selfcheck") {
    selfCheck()
    exit(0)
}
if args.contains("--config") {
    Cfg.ensureTemplateWritten()
    print(Cfg.url.path)
    exit(0)
}

let cfg = Cfg.load()
if args.contains("--json") { exit(cliExit(cfg, wantJSON: true)) }
if args.contains("--text") { exit(cliExit(cfg, wantJSON: false)) }

let app = NSApplication.shared
let agent = Agent()
agent.start()
agent.restoreAuto()
app.run()
