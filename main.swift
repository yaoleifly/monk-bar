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
//  用量接口与官网账户页相同：POST https://monk.party/monk-api/lookup-order
//  body {"email":..}，多卡时再带 {"tradeNo":..}。
//  2026-10 起响应只给 Key 末四位（apiKeyMasked），完整 sk-monk-* 在购买邮件里。
//  付费 Key 可调用 monk / monk-fast / monk-coding / monk-free。Base URL https://monk.party/v1。
//  自动刷新默认关闭，手动 ⌘R。
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

// MARK: - 当前服务常量（缺字段时的兜底；响应里的数字优先）

enum AppMeta {
    /// 与 build.sh 里的 CFBundleShortVersionString 保持一致。
    static let version = "1.6.0"
}

struct MonkModelOption: Identifiable {
    let name: String
    let blurb: String
    var id: String { name }
}

enum MonkCatalog {
    static let baseURL = "https://monk.party/v1"
    static let pingModel = "monk-fast"
    static let options: [MonkModelOption] = [
        MonkModelOption(name: "monk", blurb: "默认"),
        MonkModelOption(name: "monk-fast", blurb: "极速"),
        MonkModelOption(name: "monk-coding", blurb: "代码"),
        MonkModelOption(name: "monk-free", blurb: "均可"),
    ]
}

enum MonkLimits {
    /// 公开默认值，见 2026-10-14 llms-full.txt。服务端 fairness / dailyLimit 一律优先。
    static let daily = 200.0
    static let hourMax = 800.0
    static let hourPrompt = 60_000_000.0
    static let sixHourMax = 2_400.0
    static let sixHourPrompt = 90_000_000.0
}

/// 购买邮件里的完整 Key。掩码（含 •）和空串都不当成可调用密钥。
func isFullKey(_ raw: String?) -> String? {
    var k = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if k.lowercased().hasPrefix("bearer ") {
        k = String(k.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    guard k.count >= 12,
          k.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          k.hasPrefix("sk-monk-") || k.hasPrefix("monk-")
    else { return nil }
    return k
}

func lookupFailureMessage(status: Int, error: String?) -> String {
    let raw = error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if status == 429 || raw.localizedCaseInsensitiveContains("too many") {
        return "查询太频繁，请稍后再试。"
    }
    if status == 404 || raw == "No matching order." || raw == "Not Found" {
        return "未查到该邮箱的已支付订单。"
    }
    if !raw.isEmpty { return raw }
    return "查询失败 (HTTP \(status))"
}

func usableKeys(_ keys: [KeyItem]) -> [KeyItem] {
    keys.filter { $0.expired != true }
}

func maskedKey(_ key: String?) -> String {
    guard let key, !key.isEmpty else { return "sk-monk-••••" }
    if key.contains("•") || key.count <= 12 { return key }
    let head = key.hasPrefix("sk-monk-") ? "sk-monk-" : String(key.prefix(7))
    return head + "…" + String(key.suffix(4))
}

// MARK: - 配置

struct Config: Codable {
    var email: String
    var tradeNo: String?
    /// 只留在本机，供连通性测试。用量查询不上传这个字段。
    var apiKey: String?
}

enum Cfg {
    static let endpoint = URL(string: "https://monk.party/monk-api/lookup-order")!
    static let accountPage = URL(string: "https://monk.party/account/")!
    static let helpPage = URL(string: "https://monk.party/help/")!
    static let charterPage = URL(string: "https://monk.party/charter/")!
    static let homePage = URL(string: "https://monk.party/")!

    /// 账户页会读取 ?email= 与 ?trade= 并自动查询，续费同一把 Key 也在这一页。
    static func accountURL(email: String?, tradeNo: String?) -> URL {
        guard var parts = URLComponents(url: accountPage, resolvingAgainstBaseURL: false) else { return accountPage }
        var items: [URLQueryItem] = []
        let mail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trade = tradeNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !mail.isEmpty { items.append(URLQueryItem(name: "email", value: mail)) }
        if !trade.isEmpty { items.append(URLQueryItem(name: "trade", value: trade)) }
        if !items.isEmpty { parts.queryItems = items }
        return parts.url ?? accountPage
    }

    static var dir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let d = base.appendingPathComponent("MonkUsage", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var url: URL { dir.appendingPathComponent("config.json") }

    static let template = "{\n  \"email\": \"you@example.com\"\n}\n"

    static func load() -> Config? {
        let env = ProcessInfo.processInfo.environment
        if let e = env["MONK_EMAIL"], !e.isEmpty {
            let t = env["MONK_TRADENO"]
            let k = env["MONK_API_KEY"]
            return Config(
                email: e,
                tradeNo: (t?.isEmpty == false) ? t : nil,
                apiKey: isFullKey(k)
            )
        }
        guard let data = try? Data(contentsOf: url),
              var c = try? JSONDecoder().decode(Config.self, from: data),
              !c.email.isEmpty, c.email.contains("@"), !c.email.contains("example.com")
        else { return nil }
        if isFullKey(c.apiKey) == nil, let k = isFullKey(env["MONK_API_KEY"]) {
            c.apiKey = k
        } else {
            c.apiKey = isFullKey(c.apiKey)
        }
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

// MARK: - 自动更新检查 (GitHub Releases API)

struct UpdateInfo {
    let latestVersion: String
    let releaseNotes: String?
    let htmlURL: URL
    let downloadURL: URL?
}

enum UpdateChecker {
    static let apiURL = URL(string: "https://api.github.com/repos/yaoleifly/monk-bar/releases/latest")!
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppMeta.version

    /// 比较 semver：latest > current 返回 true
    static func isNewer(latest: String, current: String) -> Bool {
        let cleanLatest = latest.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)
        let v1 = cleanLatest.split(separator: ".").compactMap { Int($0) }
        let v2 = cleanCurrent.split(separator: ".").compactMap { Int($0) }
        for (a, b) in zip(v1, v2) {
            if a > b { return true }
            if a < b { return false }
        }
        return v1.count > v2.count
    }

    static func check(completion: @escaping (UpdateInfo?, String?) -> Void) {
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("MonkBar-macOS-Updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            let main: (UpdateInfo?, String?) -> Void = { u, e in
                DispatchQueue.main.async { completion(u, e) }
            }
            if let err = err {
                main(nil, err.localizedDescription)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlUrlStr = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlUrlStr) else {
                main(nil, "无法解析 GitHub 更新数据")
                return
            }

            let notes = json["body"] as? String
            var dlURL: URL? = nil
            if let assets = json["assets"] as? [[String: Any]],
               let first = assets.first,
               let dlStr = first["browser_download_url"] as? String {
                dlURL = URL(string: dlStr)
            }

            if isNewer(latest: tagName, current: currentVersion) {
                let info = UpdateInfo(
                    latestVersion: tagName,
                    releaseNotes: notes,
                    htmlURL: htmlURL,
                    downloadURL: dlURL
                )
                main(info, nil)
            } else {
                main(nil, nil)
            }
        }.resume()
    }
}

// MARK: - 接口模型

struct UsageWindow: Codable {
    var n: Double?
    var w: Double?
    var pin: Double?
}

struct RateLimit: Codable {
    var limited: Bool?
    var reason: String?
    var retryAt: String?
    var retryAfter: Double?
    var hour: UsageWindow?
    var six: UsageWindow?

    init(limited: Bool? = nil, reason: String? = nil, retryAt: String? = nil, retryAfter: Double? = nil, hour: UsageWindow? = nil, six: UsageWindow? = nil) {
        self.limited = limited
        self.reason = reason
        self.retryAt = retryAt
        self.retryAfter = retryAfter
        self.hour = hour
        self.six = six
    }
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

struct KeyItem: Codable, Identifiable {
    var id: String { tradeNo ?? UUID().uuidString }
    var tradeNo: String?
    var apiKeyMasked: String?
    var paidAt: String?
    var createdAt: String?
    var expiresAt: String?
    var expired: Bool?
    var keyActive: Bool?
    var remainingMs: Double?
    var soon: Bool?
    var latest: Bool?
}

struct Order: Codable {
    var apiKey: String?
    var apiKeyMasked: String?
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

    /// 账户页现在只下发掩码。旧响应若仍带完整 apiKey，显示时再截短。
    var displayKey: String { apiKeyMasked ?? apiKey ?? "sk-monk-••••" }

    init(apiKey: String? = nil, apiKeyMasked: String? = nil, tradeNo: String? = nil, status: String? = nil, createdAt: String? = nil, paidAt: String? = nil, expiresAt: String? = nil, remainingMs: Double? = nil, expired: Bool? = nil, soon: Bool? = nil, keyActive: Bool? = nil, dailyCost: Double? = nil, dailyLimit: Double? = nil, tokens: Tokens? = nil, fairness: Fairness? = nil, rateLimit: RateLimit? = nil, cooldownUntil: String? = nil) {
        self.apiKey = apiKey
        self.apiKeyMasked = apiKeyMasked
        self.tradeNo = tradeNo
        self.status = status
        self.createdAt = createdAt
        self.paidAt = paidAt
        self.expiresAt = expiresAt
        self.remainingMs = remainingMs
        self.expired = expired
        self.soon = soon
        self.keyActive = keyActive
        self.dailyCost = dailyCost
        self.dailyLimit = dailyLimit
        self.tokens = tokens
        self.fairness = fairness
        self.rateLimit = rateLimit
        self.cooldownUntil = cooldownUntil
    }
}

/// 响应里的完整 Key 优先，否则用本机配置。掩码不能拿去调用。
func fullApiKey(order: Order?) -> String? {
    if let k = isFullKey(order?.apiKey) { return k }
    return isFullKey(Cfg.load()?.apiKey)
}

struct Root: Codable {
    var success: Bool?
    var keys: [KeyItem]?
    var order: Order?
    var error: String?
}

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
    func lookup(_ cfg: Config, completion: @escaping (Order?, [KeyItem]?, String?) -> Void) {
        var req = URLRequest(url: Cfg.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var bodyDict: [String: Any] = ["email": cfg.email]
        if let t = cfg.tradeNo, !t.isEmpty {
            bodyDict["tradeNo"] = t
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)
        if cached != nil, let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        session.dataTask(with: req) { [weak self] data, resp, err in
            let main: (Order?, [KeyItem]?, String?) -> Void = { o, k, e in
                DispatchQueue.main.async { completion(o, k, e) }
            }
            if let err {
                main(nil, nil, "网络错误：\(err.localizedDescription)")
                return
            }
            guard let http = resp as? HTTPURLResponse, let data else {
                main(nil, nil, "响应异常")
                return
            }
            if http.statusCode == 304, let self, let c = self.cached {
                main(c, nil, nil)
                return
            }
            guard let root = try? JSONDecoder().decode(Root.self, from: data) else {
                main(nil, nil, "无法解析响应 (HTTP \(http.statusCode))")
                return
            }
            switch (http.statusCode, root.success, root.order) {
            case (200, true, let o?):
                if let tag = http.value(forHTTPHeaderField: "ETag") { self?.etag = tag }
                self?.cached = o
                if o.status != "paid" {
                    main(o, root.keys, "订单尚未完成支付。")
                } else {
                    main(o, root.keys, nil)
                }
            case (404, _, _), (429, _, _):
                main(nil, nil, lookupFailureMessage(status: http.statusCode, error: root.error))
            default:
                main(nil, nil, lookupFailureMessage(status: http.statusCode, error: root.error))
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

    // 1. 冷却中
    if let cd = Fmt.parse(o.cooldownUntil), cd.timeIntervalSinceNow > 0 {
        return ("冷却中 · " + Fmt.rel(o.cooldownUntil) + "解除", true)
    }

    // 2. 持续限流中 (带原因)
    if o.rateLimit?.limited == true {
        let until = o.rateLimit?.retryAt != nil ? Fmt.rel(o.rateLimit?.retryAt) + "恢复" : "请降并发"
        let reason = o.rateLimit?.reason != nil ? " (\(o.rateLimit!.reason!))" : ""
        return ("限流中 · \(until)\(reason)", true)
    }

    // 3. Retry-After 临时退避
    if let retry = o.rateLimit?.retryAfter, retry > 0 {
        return ("限流中 · \(Int(retry))s 后重试", true)
    }

    // 4. 今日保险丝打满
    if let limit = o.dailyLimit, limit > 0, (o.dailyCost ?? 0) >= limit {
        return ("今日熔断 · UTC 00:00 清零", true)
    }

    // 5. 1小时窗口达到上限
    if let r = o.rateLimit?.hour, let f = o.fairness {
        if let w = r.w, let maxW = f.hourMax, maxW > 0, w >= maxW {
            return ("1h 次数超限", true)
        }
        if let pin = r.pin, let maxPin = f.hourPrompt, maxPin > 0, pin >= maxPin {
            return ("1h Token 超限", true)
        }
    }

    // 6. 6小时窗口达到上限
    if let r = o.rateLimit?.six, let f = o.fairness {
        if let w = r.w, let maxW = f.sixHourMax, maxW > 0, w >= maxW {
            return ("6h 次数超限", true)
        }
        if let pin = r.pin, let maxPin = f.sixHourPrompt, maxPin > 0, pin >= maxPin {
            return ("6h Token 超限", true)
        }
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
        "近 14 天 \(Fmt.tok(o.tokens?.total))（入 \(Fmt.tok(o.tokens?.prompt)) · 出 \(Fmt.tok(o.tokens?.completion))）",
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
        let lim = max(0.01, limit ?? MonkLimits.daily)
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

// MARK: - 系统适配与信息 (macOS 13+；26 Tahoe，27 Golden Gate)

enum SystemInfo {
    static func marketingName(major: Int, minor: Int) -> String {
        switch major {
        case 27:
            return "macOS Golden Gate (27.\(minor))"
        case 26:
            return "macOS Tahoe (26.\(minor))"
        case 15:
            return "macOS Sequoia (15.\(minor))"
        case 14:
            return "macOS Sonoma (14.\(minor))"
        case 13:
            return "macOS Ventura (13.\(minor))"
        default:
            return "macOS (\(major).\(minor))"
        }
    }

    static var macOSName: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return marketingName(major: v.majorVersion, minor: v.minorVersion)
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
    var autoCheckUpdates = true
    var availableUpdate: UpdateInfo? = nil
    var timer: Timer?

    func start() {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        displayMode = StatusDisplayMode(rawValue: UserDefaults.standard.string(forKey: "monkStatusDisplayMode") ?? "") ?? .detailed
        autoCheckUpdates = UserDefaults.standard.object(forKey: "monkAutoCheckUpdates") as? Bool ?? true
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
        // 启动后延迟 3 秒静默检查更新（若开启了自动检查）
        if autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }
    }

    /// 在 Accessory 模式下注册系统级 Edit 菜单，激活 ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 原生快捷键
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func setAttributedTitle(_ attr: NSAttributedString, tip: String) {
        item.button?.attributedTitle = attr
        item.button?.toolTip = tip
    }

    var keys: [KeyItem] = []

    func refreshIfNeeded() {
        guard let cfg = Cfg.load() else {
            setOrder(nil, keys: [], note: "未配置：请填写下单邮箱")
            return
        }
        fetcher.lookup(cfg) { [weak self] o, k, e in
            guard let self = self else { return }
            self.setOrder(o ?? self.order, keys: k ?? self.keys, note: e)
        }
    }

    func setOrder(_ o: Order?, keys: [KeyItem]?, note: String?) {
        self.order = o
        if let keys = keys { self.keys = keys }
        self.note = note
        self.render()
        DispatchQueue.main.async {
            SettingsWindowController.shared.update(order: o, keys: keys, note: note)
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

        // 发现新版本
        if let update = availableUpdate {
            let updateItem = NSMenuItem(title: "✨ 新版本 \(update.latestVersion) · 更新 ↗", action: #selector(doOpenUpdate), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        // 临期续费
        if let o = order, isExpiringSoon(o) {
            let daysLeft = Fmt.left(o.remainingMs, expired: o.expired == true)
            let title = o.expired == true ? "⚠️ 订阅已到期 · 续订 ↗" : "🔥 仅剩 \(daysLeft) · 续订 ↗"
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

        let styleItem = NSMenuItem(title: "显示样式", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu(title: "显示样式")
        let modeDetailed = NSMenuItem(title: "详细 (额度 + 百分比 + 剩余)", action: #selector(selectModeDetailed), keyEquivalent: "")
        modeDetailed.target = self
        modeDetailed.state = displayMode == .detailed ? .on : .off
        styleSubmenu.addItem(modeDetailed)

        let modeCompact = NSMenuItem(title: "紧凑 (仅今日额度)", action: #selector(selectModeCompact), keyEquivalent: "")
        modeCompact.target = self
        modeCompact.state = displayMode == .compact ? .on : .off
        styleSubmenu.addItem(modeCompact)

        let modeIconOnly = NSMenuItem(title: "仅图标 (极简)", action: #selector(selectModeIconOnly), keyEquivalent: "")
        modeIconOnly.target = self
        modeIconOnly.state = displayMode == .iconOnly ? .on : .off
        styleSubmenu.addItem(modeIconOnly)

        styleItem.submenu = styleSubmenu
        menu.addItem(styleItem)

        let auto = NSMenuItem(title: "后台刷新 (5分钟)", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = autoRefresh ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())
        let acct = NSMenuItem(title: "打开账户页 ↗", action: #selector(doAccount), keyEquivalent: "a")
        acct.keyEquivalentModifierMask = [.command, .shift]
        acct.target = self
        menu.addItem(acct)

        let monkPiItem = NSMenuItem(title: "推荐 Monk-Pi ↗", action: #selector(doOpenMonkPi), keyEquivalent: "")
        monkPiItem.target = self
        menu.addItem(monkPiItem)

        let charterItem = NSMenuItem(title: "使用倡议书 ↗", action: #selector(doCharter), keyEquivalent: "")
        charterItem.target = self
        menu.addItem(charterItem)

        let helpItem = NSMenuItem(title: "帮助中心 ↗", action: #selector(doHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())
        let conf = NSMenuItem(title: "设置…", action: #selector(doSettings), keyEquivalent: ",")
        conf.target = self
        menu.addItem(conf)

        let checkUpdateItem = NSMenuItem(title: "检查更新…", action: #selector(doCheckUpdateManual), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func addOrderItems(to menu: NSMenu, _ o: Order) {
        let st = state(o)
        menu.addItem(info("状态　\(st.label)"))
        if fullApiKey(order: o) != nil {
            menu.addItem(info("Key　　\(masked(o.displayKey))　(复制)", action: #selector(doCopyKey), target: self))
        } else {
            menu.addItem(info("Key　　\(masked(o.displayKey))　(完整密钥在购买邮件)"))
        }
        menu.addItem(info("剩余　\(Fmt.left(o.remainingMs, expired: o.expired == true)) · 到期 \(Fmt.date(o.expiresAt))"))
        if let opened = o.paidAt ?? o.createdAt {
            menu.addItem(info("开通　\(Fmt.date(opened))"))
        }
        menu.addItem(info("今日　\(Fmt.bar(o.dailyCost, o.dailyLimit)) \(Fmt.money(o.dailyCost)) / \(Fmt.money(o.dailyLimit))"))
        menu.addItem(info("近14天　\(Fmt.tok(o.tokens?.total)) (入 \(Fmt.tok(o.tokens?.prompt)) · 出 \(Fmt.tok(o.tokens?.completion)))"))
        menu.addItem(info("模型　monk · monk-fast · monk-coding · monk-free"))

        if let r = o.rateLimit, let fair = o.fairness {
            menu.addItem(.separator())
            menu.addItem(info("1 小时　\(Fmt.num(r.hour?.w))/\(Fmt.num(fair.hourMax)) 次 · \(Fmt.tok(r.hour?.pin)) in"))
            menu.addItem(info("6 小时　\(Fmt.num(r.six?.w))/\(Fmt.num(fair.sixHourMax)) 次 · \(Fmt.tok(r.six?.pin)) in"))
            menu.addItem(info("并发　　每Key \(Fmt.num(fair.inflightPerKey)) 路 · 全站 \(Fmt.num(fair.inflightGlobal)) 路"))
        }
        if let cd = o.cooldownUntil, Fmt.parse(cd)?.timeIntervalSinceNow ?? -1 > 0 {
            menu.addItem(info("冷却　　至 \(Fmt.date(cd))"))
        }
    }

    func masked(_ key: String?) -> String { maskedKey(key) }

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
        let cfg = Cfg.load()
        let trade = order?.tradeNo ?? cfg?.tradeNo
        NSWorkspace.shared.open(Cfg.accountURL(email: cfg?.email, tradeNo: trade))
    }

    @objc func doHelp() {
        NSWorkspace.shared.open(Cfg.helpPage)
    }

    @objc func doCharter() {
        NSWorkspace.shared.open(Cfg.charterPage)
    }

    @objc func doOpenUpdate() {
        if let update = availableUpdate {
            NSWorkspace.shared.open(update.downloadURL ?? update.htmlURL)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/yaoleifly/monk-bar/releases")!)
        }
    }

    @objc func doCheckUpdateManual() {
        checkForUpdates(silent: false)
    }

    func setAutoCheckUpdates(_ enabled: Bool) {
        self.autoCheckUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "monkAutoCheckUpdates")
    }

    func checkForUpdates(silent: Bool, completion: ((Bool) -> Void)? = nil) {
        UpdateChecker.check { [weak self] info, err in
            guard let self = self else { return }
            self.availableUpdate = info
            self.item.menu?.delegate?.menuNeedsUpdate?(self.item.menu!)

            if let info = info {
                if !silent {
                    self.promptUpdateAvailable(info)
                }
                completion?(true)
            } else {
                if !silent {
                    if let err = err {
                        let alert = NSAlert()
                        alert.messageText = "检查更新失败"
                        alert.informativeText = "无法连接至 GitHub (\(err))，请检查网络。"
                        alert.addButton(withTitle: "好")
                        alert.runModal()
                    } else {
                        self.promptUpToDate()
                    }
                }
                completion?(false)
            }
        }
    }

    func promptUpdateAvailable(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "发现 MonkBar 新版本 \(info.latestVersion)"
        alert.informativeText = "当前版本：v\(UpdateChecker.currentVersion)\n最新版本：\(info.latestVersion)"
        alert.addButton(withTitle: "前往下载更新")
        alert.addButton(withTitle: "稍后再说")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(info.downloadURL ?? info.htmlURL)
        }
    }

    func promptUpToDate() {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "MonkBar v\(UpdateChecker.currentVersion) 已是最新版。"
        alert.addButton(withTitle: "好")
        alert.runModal()
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
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.refreshIfNeeded()
            }
            refreshIfNeeded()
        }
        item.menu?.delegate?.menuNeedsUpdate?(item.menu!)
    }

    @objc func doAccount() {
        let cfg = Cfg.load()
        let trade = order?.tradeNo ?? cfg?.tradeNo
        NSWorkspace.shared.open(Cfg.accountURL(email: cfg?.email, tradeNo: trade))
    }

    @objc func doSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show(agent: self)
    }

    @objc func doConfig() {
        Cfg.ensureTemplateWritten()
        NSWorkspace.shared.open(Cfg.url)
    }

    @objc func doCopyKey() {
        guard let key = fullApiKey(order: order) else {
            note = "查询只返回末四位。完整 Key 在购买邮件里，可填到设置里的「本机 Key」。"
            render()
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(key, forType: .string)
        note = "API Key 已复制"
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

// MARK: - 精简高效设置面板与实时看板 (SwiftUI + AppKit)

final class SettingsViewModel: ObservableObject {
    @Published var order: Order? = nil
    @Published var keys: [KeyItem] = []
    @Published var pingStatus: String? = nil
    @Published var isPinging: Bool = false
    @Published var email: String = ""
    @Published var tradeNo: String = ""
    @Published var apiKey: String = ""
    @Published var autoRefresh: Bool = false
    @Published var statusDisplayMode: StatusDisplayMode = .detailed
    @Published var autoCheckUpdates: Bool = true
    @Published var checkingUpdate: Bool = false
    @Published var updateResultNote: String? = nil
    @Published var validationError: String? = nil
    @Published var saveSuccess: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var copiedKey: Bool = false
    @Published var copiedBaseURL: Bool = false
    @Published var copiedEmail: Bool = false
    @Published var copiedTradeNo: Bool = false
    @Published var copiedMonkPiNpx: Bool = false
    @Published var copiedMonkPiBrew: Bool = false

    weak var agent: Agent?

    func loadFromCurrent(agent: Agent) {
        self.agent = agent
        self.order = agent.order
        self.keys = agent.keys
        let cfg = Cfg.load()
        self.email = cfg?.email ?? ""
        self.tradeNo = cfg?.tradeNo ?? ""
        self.apiKey = cfg?.apiKey ?? ""
        self.autoRefresh = agent.autoRefresh
        self.statusDisplayMode = agent.displayMode
        self.autoCheckUpdates = agent.autoCheckUpdates
        self.validationError = nil
        self.saveSuccess = false
        self.copiedKey = false
        self.copiedBaseURL = false
        self.copiedEmail = false
        self.copiedTradeNo = false
        self.copiedMonkPiNpx = false
        self.copiedMonkPiBrew = false
    }

    func copyEmail() {
        guard !email.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(email, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedEmail = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedEmail = false }
        }
    }

    func pasteEmail() {
        if let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            self.email = s
        }
    }

    func copyTradeNo() {
        guard !tradeNo.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tradeNo, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedTradeNo = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedTradeNo = false }
        }
    }

    func pasteTradeNo() {
        if let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            self.tradeNo = s
        }
    }

    func pasteApiKey() {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        self.apiKey = isFullKey(s) ?? s
    }

    func copyKey(_ key: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(key, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedKey = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedKey = false }
        }
    }

    func copyBaseURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(MonkCatalog.baseURL, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedBaseURL = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedBaseURL = false }
        }
    }

    func copyMonkPiNpx() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("npx monk-pi", forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedMonkPiNpx = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedMonkPiNpx = false }
        }
    }

    func copyMonkPiBrew() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("brew install yaoleifly/tap/monk-pi", forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedMonkPiBrew = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation { self?.copiedMonkPiBrew = false }
        }
    }

    func openMonkPiGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yaoleifly/monk-pi")!)
    }

    func openPricing() {
        let trade = order?.tradeNo ?? (tradeNo.isEmpty ? nil : tradeNo)
        NSWorkspace.shared.open(Cfg.accountURL(email: email, tradeNo: trade))
    }

    func openHelp() {
        NSWorkspace.shared.open(Cfg.helpPage)
    }

    func openHome() {
        NSWorkspace.shared.open(Cfg.homePage)
    }

    func openCharter() {
        NSWorkspace.shared.open(Cfg.charterPage)
    }

    func refreshNow() {
        guard let agent = agent, Cfg.load() != nil else { return }
        withAnimation(.easeInOut(duration: 0.15)) { isRefreshing = true }
        agent.refreshIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            withAnimation { self?.isRefreshing = false }
        }
    }

    func checkUpdateManual() {
        checkingUpdate = true
        updateResultNote = nil
        agent?.checkForUpdates(silent: false) { [weak self] hasUpdate in
            self?.checkingUpdate = false
            if !hasUpdate {
                self?.updateResultNote = "已是最新版"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self?.updateResultNote = nil
                }
            }
        }
    }

    func selectTradeNo(_ no: String) {
        self.tradeNo = no
        let typed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept: String?
        if typed.isEmpty {
            kept = nil
        } else {
            kept = isFullKey(typed) ?? Cfg.load()?.apiKey
        }
        Cfg.save(Config(email: email, tradeNo: no, apiKey: kept))
        withAnimation { isRefreshing = true }
        agent?.refreshIfNeeded()
    }

    func pingModel() {
        guard let key = fullApiKey(order: order ?? agent?.order) else {
            pingStatus = "没有完整 Key。查询只给末四位，把购买邮件里的 sk-monk-… 填到「本机 Key」。"
            return
        }
        isPinging = true
        pingStatus = "正在测试调用 \(MonkCatalog.pingModel)…"

        let start = Date()
        var req = URLRequest(url: URL(string: MonkCatalog.baseURL + "/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let payload: [String: Any] = [
            "model": MonkCatalog.pingModel,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 5
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            DispatchQueue.main.async {
                self?.isPinging = false
                if let err = err {
                    self?.pingStatus = "❌ 网络错误: \(err.localizedDescription)"
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    self?.pingStatus = "❌ 响应异常"
                    return
                }

                if http.statusCode == 200 {
                    self?.pingStatus = "✅ 响应正常 (\(ms)ms) · 未被限流"
                    self?.agent?.refreshIfNeeded()
                } else if http.statusCode == 429 {
                    var detail = "429 限流中"
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let msg = (json["error"] as? [String: Any])?["message"] as? String {
                            detail = msg
                        } else if let msg = json["error"] as? String {
                            detail = msg
                        } else if let msg = json["message"] as? String {
                            detail = msg
                        }
                    }
                    self?.pingStatus = "⚠️ 429 限流: \(detail)"
                    self?.agent?.refreshIfNeeded()
                } else {
                    self?.pingStatus = "HTTP \(http.statusCode)"
                }
            }
        }.resume()
    }

    func saveAndRefresh() {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = tradeNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if e.isEmpty || !e.contains("@") {
            validationError = "请填写有效下单邮箱"
            saveSuccess = false
            return
        }
        let storedKey: String?
        if rawKey.isEmpty {
            storedKey = nil
        } else if let k = isFullKey(rawKey) {
            storedKey = k
            apiKey = k
        } else {
            validationError = "本机 Key 应以 sk-monk- 开头，或留空"
            saveSuccess = false
            return
        }

        validationError = nil
        Cfg.save(Config(email: e, tradeNo: t.isEmpty ? nil : t, apiKey: storedKey))

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
            if agent.autoCheckUpdates != autoCheckUpdates {
                agent.setAutoCheckUpdates(autoCheckUpdates)
            }
            withAnimation { isRefreshing = true }
            agent.note = nil
            agent.refreshIfNeeded()
        }

        withAnimation(.spring()) {
            saveSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(badgeColor.opacity(0.12))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }
            }
            content
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(colors: tintColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * pct), height: 6)
            }
        }
        .frame(height: 6)
    }
}

struct TokenSegmentBar: View {
    var prompt: Double
    var completion: Double

    var total: Double { max(1, prompt + completion) }
    var promptPct: Double { prompt / total }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * promptPct))
                    Capsule()
                        .fill(LinearGradient(colors: [Visuals.flameOrange, Visuals.flameGold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * (1.0 - promptPct)))
                }
            }
            .frame(height: 6)

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("输入: \(Fmt.tok(prompt)) (\(String(format: "%.1f", promptPct * 100))%)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Visuals.flameOrange).frame(width: 6, height: 6)
                    Text("输出: \(Fmt.tok(completion)) (\(String(format: "%.1f", (1.0 - promptPct) * 100))%)")
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
        VStack(alignment: .leading, spacing: 3) {
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
            // Header
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // 主体
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    // 新版本提示
                    if let u = model.agent?.availableUpdate {
                        updateBanner(u)
                    }

                    // 多卡切换器 (若名下有多张卡)
                    keySwitcher

                    if let o = model.order {
                        // 临期提醒
                        if isExpiringSoon(o) {
                            renewalBanner(o)
                        }
                        // Bento Grid
                        liveDashboard(o)
                    } else {
                        unconfiguredCard
                    }

                    // Monk-Pi 工具
                    monkPiRecommendationCard

                    // 凭据设置
                    credentialsCard

                    // 偏好设置
                    preferencesCard
                }
                .padding(16)
            }

            Divider()

            // 底部操作栏
            bottomActionBar
        }
        .frame(width: 530, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(nsImage: Visuals.appIconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MonkBar")
                        .font(.system(size: 15, weight: .bold))
                    statusBadge
                }
                HStack(spacing: 4) {
                    Text("四个融合模型")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(SystemInfo.macOSName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                model.refreshNow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(model.isRefreshing ? .degrees(360) : .zero)
                        .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
                    Text(model.isRefreshing ? "同步中…" : "刷新")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isRefreshing || Cfg.load() == nil)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let o = model.order {
            let st = state(o)
            Text(st.label)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(st.bad ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                .foregroundStyle(st.bad ? Color.red : Color.green)
                .clipShape(Capsule())
        } else if Cfg.load() == nil {
            Text("未配置")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(Color.orange)
                .clipShape(Capsule())
        } else {
            Text("连接异常")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color.red)
                .clipShape(Capsule())
        }
    }

    // MARK: - 新版本提示横幅
    @ViewBuilder
    private func updateBanner(_ u: UpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(.blue)

            Text("新版本 \(u.latestVersion)")
                .font(.caption.weight(.semibold))

            Text("(当前 v\(UpdateChecker.currentVersion))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button("更新 ↗") {
                NSWorkspace.shared.open(u.downloadURL ?? u.htmlURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 多卡切换器 (若有多张卡)
    @ViewBuilder
    private var keySwitcher: some View {
        let usable = usableKeys(model.keys)
        if usable.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("名下卡片 (\(usable.count) 张)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("点击切换")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(usable) { k in
                            let isSelected = (k.tradeNo == model.order?.tradeNo) || (model.tradeNo.isEmpty && k.latest == true)
                            let mask = k.apiKeyMasked ?? "••••"
                            let short = mask.count > 8 ? String(mask.suffix(4)) : mask
                            let days = Int((k.remainingMs ?? 0) / 1000 / 86400)

                            Button {
                                if let t = k.tradeNo {
                                    model.selectTradeNo(t)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(isSelected ? Visuals.flameOrange : (k.keyActive == true ? Color.green : Color.secondary))
                                        .frame(width: 6, height: 6)

                                    Text("••••\(short)")
                                        .font(.system(.caption2, design: .monospaced).weight(.semibold))

                                    Text("· \(days)d")
                                        .font(.caption2)

                                    if k.latest == true {
                                        Text("最新")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Visuals.flameOrange.opacity(0.15))
                                            .foregroundStyle(Visuals.flameOrange)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isSelected ? Visuals.flameOrange.opacity(0.12) : Color.primary.opacity(0.04))
                                .foregroundStyle(isSelected ? Visuals.flameOrange : .primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Visuals.flameOrange.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 到期续费横幅
    @ViewBuilder
    private func renewalBanner(_ o: Order) -> some View {
        let daysLeft = Fmt.left(o.remainingMs, expired: o.expired == true)
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundStyle(Visuals.flameOrange)

            Text(o.expired == true ? "套餐已到期" : "套餐即将到期")
                .font(.caption.weight(.bold))
                .foregroundStyle(Visuals.flameOrange)

            Text("剩余 \(daysLeft) · 到期 \(Fmt.date(o.expiresAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button("续费 ↗") {
                model.openPricing()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Visuals.flameOrange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Visuals.flameOrange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Bento Grid 实时用量
    private func liveDashboard(_ o: Order) -> some View {
        VStack(spacing: 10) {
            // Row 1: 今日内部计量 + 订阅有效期限
            HStack(spacing: 10) {
                let cost = o.dailyCost ?? 0
                let limit = max(0.01, o.dailyLimit ?? MonkLimits.daily)
                let pct = Int(min(100, max(0, (cost / limit) * 100)))

                MetricCard(title: "今日内部计量", icon: "flame.fill", iconColor: Visuals.flameOrange, badge: "保险丝", badgeColor: Visuals.flameOrange) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.money(cost))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(pct > 80 ? .red : .primary)
                            Text("/ \(Fmt.money(limit))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(pct)%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(pct > 80 ? .red : Visuals.flameOrange)
                        }

                        GaugeBar(value: cost, total: limit, tintColors: pct > 80 ? [.red, .orange] : [Visuals.flameOrange, Visuals.flameGold])

                        HStack {
                            Text("剩余 \(Fmt.money(max(0, limit - cost)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("UTC 00:00 清零")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                let (days, hours) = parseDaysHours(o.remainingMs)
                let st = state(o)

                MetricCard(title: "有效期限", icon: "calendar", iconColor: .blue, badge: st.label, badgeColor: st.bad ? .red : .green) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if o.expired == true {
                                Text("已到期")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(days)").font(.system(size: 18, weight: .bold, design: .rounded))
                                Text("天").font(.caption2).foregroundStyle(.secondary)
                                Text("\(hours)").font(.system(size: 16, weight: .bold, design: .rounded))
                                Text("时").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Text("到期: \(Fmt.date(o.expiresAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let cd = o.cooldownUntil, Fmt.parse(cd)?.timeIntervalSinceNow ?? -1 > 0 {
                            Text("冷却至 \(Fmt.date(cd))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Row 2: Token 消耗
            if let tok = o.tokens, let total = tok.total, total > 0 {
                MetricCard(title: "近 14 天 Token", icon: "gauge", iconColor: .indigo, badge: "\(Fmt.tok(total))", badgeColor: .indigo) {
                    TokenSegmentBar(prompt: tok.prompt ?? 0, completion: tok.completion ?? 0)
                }
            }

            // Row 3: 限流保护与调度
            if let r = o.rateLimit, let fair = o.fairness {
                MetricCard(title: "限流保护", icon: "shield.fill", iconColor: .teal, badge: "防 429", badgeColor: .teal) {
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1 小时窗口").font(.caption2.weight(.semibold))
                                RateLimitRow(title: "加权请求", current: r.hour?.w ?? 0, maxVal: fair.hourMax ?? MonkLimits.hourMax, isToken: false)
                                RateLimitRow(title: "输入 Token", current: r.hour?.pin ?? 0, maxVal: fair.hourPrompt ?? MonkLimits.hourPrompt, isToken: true)
                            }
                            Divider().frame(height: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("6 小时窗口").font(.caption2.weight(.semibold))
                                RateLimitRow(title: "加权请求", current: r.six?.w ?? 0, maxVal: fair.sixHourMax ?? MonkLimits.sixHourMax, isToken: false)
                                RateLimitRow(title: "输入 Token", current: r.six?.pin ?? 0, maxVal: fair.sixHourPrompt ?? MonkLimits.sixHourPrompt, isToken: true)
                            }
                        }

                        HStack(spacing: 6) {
                            ruleCapsule(icon: "bolt.fill", text: "并发: 单Key \(Fmt.num(fair.inflightPerKey)) / 全站 \(Fmt.num(fair.inflightGlobal))")
                            ruleCapsule(icon: "archivebox.fill", text: "突发桶: \(Fmt.num(fair.burstCapacity)) / 补 \(Fmt.num(fair.burstRefillPerMin))")
                            ruleCapsule(icon: "shield.fill", text: "超 \(Fmt.num(fair.penalty429PerMin))次 429 罚 \(Fmt.num(fair.penaltyMinutes))分")
                        }
                        Text("权重：普通请求计 1；输入超过 3.2 万 Token 计 2；超过 8 万计 4。数字以本次查询返回为准。")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Row 4: API 与模型。查询接口只保证掩码，完整 Key 可能不在响应里。
            MetricCard(title: "API 与模型", icon: "terminal.fill", iconColor: .purple) {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Key")
                                .font(.caption.weight(.semibold))
                                .frame(width: 45, alignment: .leading)
                            Text(masked(o.displayKey))
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            if let full = fullApiKey(order: o) {
                                Button(model.copiedKey ? "已复制" : "复制") {
                                    model.copyKey(full)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text("完整 Key 在邮件")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("URL")
                                .font(.caption.weight(.semibold))
                                .frame(width: 45, alignment: .leading)
                            Text(MonkCatalog.baseURL)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button(model.copiedBaseURL ? "已复制" : "复制") {
                                model.copyBaseURL()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 6) {
                            Text("模型:").font(.caption2).foregroundStyle(.secondary)
                            ForEach(MonkCatalog.options) { item in
                                modelTag(name: item.name, desc: item.blurb)
                            }
                            Spacer()
                        }

                        Divider().padding(.vertical, 2)

                        HStack(spacing: 8) {
                            Button {
                                model.pingModel()
                            } label: {
                                HStack(spacing: 4) {
                                    if model.isPinging {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(model.isPinging ? "测试中…" : "测试连通性 (Ping)")
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.isPinging)

                            if let status = model.pingStatus {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundStyle(status.contains("✅") ? .green : .red)
                            }
                            Spacer()
                        }
                    }
                }
        }
    }

    private func ruleCapsule(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(Visuals.flameOrange)
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func modelTag(name: String, desc: String) -> some View {
        HStack(spacing: 2) {
            Text(name)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
            Text("(\(desc))")
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 未配置指引卡片
    private var unconfiguredCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 28))
                .foregroundStyle(Visuals.flameOrange)
                .padding(.top, 2)

            Text("未配置凭据")
                .font(.system(size: 13, weight: .bold))

            Text("填写下单邮箱即可查询。订单号 (MK…) 只在要指定某一张卡时才需要。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                model.openHome()
            } label: {
                Label("前往 monk.party", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Monk-Pi 推荐卡片
    private var monkPiRecommendationCard: some View {
        MetricCard(title: "推荐工具 · Monk-Pi", icon: "sparkles", iconColor: Visuals.flameOrange, badge: "终端 Agent", badgeColor: Visuals.flameOrange) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pi 终端 Coding Agent 零配置接入，预置 `monk-coding` 专属优化。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("npx monk-pi").font(.system(.caption2, design: .monospaced))
                        Spacer()
                        Button(model.copiedMonkPiNpx ? "已复制" : "复制") {
                            model.copyMonkPiNpx()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundStyle(Visuals.flameOrange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    HStack(spacing: 4) {
                        Text("brew install ...").font(.system(.caption2, design: .monospaced))
                        Spacer()
                        Button(model.copiedMonkPiBrew ? "已复制" : "复制") {
                            model.copyMonkPiBrew()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundStyle(Visuals.flameOrange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer()

                    Button {
                        model.openMonkPiGitHub()
                    } label: {
                        Text("GitHub ↗").font(.caption2)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - 账号凭据卡片
    private var credentialsCard: some View {
        MetricCard(title: "账号凭据", icon: "person.crop.circle", iconColor: .primary) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("下单邮箱").font(.caption.weight(.medium)).frame(width: 55, alignment: .leading)
                    TextField("your@email.com", text: $model.email).textFieldStyle(.roundedBorder)
                    if !model.email.isEmpty {
                        Button(model.copiedEmail ? "已复制" : "复制") { model.copyEmail() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("粘贴") { model.pasteEmail() }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                HStack(spacing: 6) {
                    Text("指定卡号").font(.caption.weight(.medium)).frame(width: 55, alignment: .leading)
                    TextField("选填 · 默认自动匹配最新卡", text: $model.tradeNo).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    if !model.tradeNo.isEmpty {
                        Button(model.copiedTradeNo ? "已复制" : "复制") { model.copyTradeNo() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("粘贴") { model.pasteTradeNo() }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                HStack(spacing: 6) {
                    Text("本机 Key").font(.caption.weight(.medium)).frame(width: 55, alignment: .leading)
                    SecureField("选填 · sk-monk-… · 只用于连通性测试", text: $model.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("粘贴") { model.pasteApiKey() }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                HStack {
                    if let err = model.validationError {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    } else {
                        Text("只需下单邮箱。查询结果只有 Key 末四位；完整密钥在购买邮件，填在「本机 Key」后才能 Ping。多张有效卡可在上方切换。月卡支付宝 ¥30 / 30 天，或 Stripe $5 / 30 天，教育邮箱（含 edu）九折。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - 偏好设置卡片
    private var preferencesCard: some View {
        MetricCard(title: "偏好设置", icon: "gearshape", iconColor: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("显示样式").font(.caption.weight(.medium))
                    Spacer()
                    Picker("", selection: $model.statusDisplayMode) {
                        ForEach(StatusDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }

                Divider()

                Toggle("后台自动刷新 (5分钟)", isOn: $model.autoRefresh)
                    .font(.caption)

                Toggle("启动时自动检查更新", isOn: $model.autoCheckUpdates)
                    .font(.caption)
                    .onChange(of: model.autoCheckUpdates) { val in
                        model.agent?.setAutoCheckUpdates(val)
                    }

                HStack {
                    Text("版本: v\(UpdateChecker.currentVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let note = model.updateResultNote {
                        Text(note).font(.caption2.weight(.medium)).foregroundStyle(.green)
                    }

                    Spacer()

                    Button(model.checkingUpdate ? "检查中…" : "检查更新") {
                        model.checkUpdateManual()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.checkingUpdate)
                }
            }
        }
    }

    // MARK: - 底部操作栏
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button("账户页 ↗") { model.openPricing() }
                .buttonStyle(.link).font(.caption)

            Button("帮助中心 ↗") { model.openHelp() }
                .buttonStyle(.link).font(.caption)

            Button("使用倡议书 ↗") { model.openCharter() }
                .buttonStyle(.link).font(.caption)

            Button("配置文件") { NSWorkspace.shared.open(Cfg.url) }
                .buttonStyle(.link).font(.caption)

            Spacer()

            if model.saveSuccess {
                Text("已保存").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }

            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)

            Button("保存") { model.saveAndRefresh() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Visuals.flameOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func masked(_ key: String) -> String { maskedKey(key) }

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

    func update(order: Order?, keys: [KeyItem]?, note: String?) {
        model.order = order
        if let keys = keys { model.keys = keys }
        model.isRefreshing = false
        if let note = note, order == nil {
            model.validationError = note
        }
        if order != nil {
            model.email = Cfg.load()?.email ?? model.email
            model.tradeNo = Cfg.load()?.tradeNo ?? model.tradeNo
        }
    }

    func show(agent: Agent) {
        model.loadFromCurrent(agent: agent)

        if window == nil {
            let view = SettingsView(model: model) { [weak self] in
                self?.window?.close()
            }
            let host = NSHostingView(rootView: view)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 530, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Monk 设置"
            win.minSize = NSSize(width: 480, height: 540)
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
    var bodyDict: [String: Any] = ["email": cfg.email]
    if let t = cfg.tradeNo, !t.isEmpty { bodyDict["tradeNo"] = t }
    req.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)
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
        guard let root = try? JSONDecoder().decode(Root.self, from: body), let o = root.order, root.success == true, (200...299).contains(status) else {
            let decoded = try? JSONDecoder().decode(Root.self, from: body)
            let msg = lookupFailureMessage(status: status, error: decoded?.error)
            FileHandle.standardError.write("monk 查询失败：\(msg)\n".data(using: .utf8)!)
            code = 1
            return
        }
        if o.status != "paid" {
            FileHandle.standardError.write("monk 查询失败：订单尚未完成支付。\n".data(using: .utf8)!)
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
    // 形状对齐 2026-10 账户页：只给 apiKeyMasked，dailyLimit 200，四窗口上限见 llms-full.txt。
    // money 用数字、并带 referral，确认多余字段不会让整包解码失败。
    let fixture = """
    {"success":true,"keys":[
      {"tradeNo":"MK123","apiKeyMasked":"sk-monk-••••abcd","expired":false,"keyActive":true,"remainingMs":1094400000,"latest":true},
      {"tradeNo":"MK999","apiKeyMasked":"••••9999","expired":true,"remainingMs":0,"latest":false}
    ],"order":{
      "apiKeyMasked":"sk-monk-••••abcd","tradeNo":"MK123","status":"paid",
      "paidAt":"2026-08-29T14:26:24.139Z",
      "expiresAt":"2026-09-28T14:26:24.139Z","remainingMs":1094400000,
      "expired":false,"soon":false,"keyActive":true,
      "dailyCost":0.4,"dailyLimit":200,
      "money":30,
      "tokens":{"prompt":1200000,"completion":30000,"total":1230000},
      "fairness":{"hourMax":800,"hourPrompt":60000000,"sixHourMax":2400,"sixHourPrompt":90000000,
                  "inflightPerKey":5,"inflightGlobal":60,"burstCapacity":80,"burstRefillPerMin":30,
                  "penalty429PerMin":40,"penaltyMinutes":8},
      "rateLimit":{"limited":false,"hour":{"w":3,"pin":120000},"six":{"w":12,"pin":1400000}},
      "cooldownUntil":"2026-10-01T00:00:00Z"
    },"referral":{"enabled":true,"url":"https://monk.party/?ref=abc"}}
    """
    let root: Root
    do { root = try JSONDecoder().decode(Root.self, from: Data(fixture.utf8)) }
    catch { fail("decode: \(error)") }
    guard let o = root.order else { fail("no order") }

    expect(o.apiKey == nil, "full key absent")
    expect(o.apiKeyMasked == "sk-monk-••••abcd", "masked key")
    expect(o.displayKey == "sk-monk-••••abcd", "display key")
    expect(o.dailyCost == 0.4 && o.dailyLimit == 200, "daily")
    expect(o.rateLimit?.hour?.w == 3 && o.rateLimit?.six?.pin == 1_400_000, "rate windows")
    expect(o.fairness?.hourMax == 800 && o.fairness?.sixHourMax == 2_400, "fairness calls")
    expect(o.fairness?.hourPrompt == 60_000_000 && o.fairness?.sixHourPrompt == 90_000_000, "fairness tokens")
    expect(o.fairness?.inflightPerKey == 5 && o.fairness?.inflightGlobal == 60, "inflight")
    expect(o.fairness?.penalty429PerMin == 40 && o.fairness?.penaltyMinutes == 8, "penalty")
    expect(o.remainingMs == 1_094_400_000, "remainingMs")
    expect(usableKeys(root.keys ?? []).compactMap(\.tradeNo) == ["MK123"], "usable keys")
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
    expect(summaryLine(o).contains("今日 ¥0.40/¥200.0"), "summary daily")
    expect(summaryLine(o).contains("1h 3/800 次"), "summary hour window")
    expect(summaryLine(o).contains("近 14 天 1.23M"), "summary tokens")
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
    expect(SystemInfo.marketingName(major: 27, minor: 0) == "macOS Golden Gate (27.0)", "golden gate")
    expect(SystemInfo.marketingName(major: 26, minor: 2) == "macOS Tahoe (26.2)", "tahoe")
    expect(SystemInfo.marketingName(major: 15, minor: 1).hasPrefix("macOS Sequoia"), "sequoia")

    let legacy = try! JSONDecoder().decode(Root.self, from: Data(
        #"{"success":true,"order":{"apiKey":"sk-monk-abcdefgh1234","dailyLimit":30,"fairness":{"hourMax":60,"inflightGlobal":8}}}"#.utf8
    ))
    expect(legacy.order?.apiKey == "sk-monk-abcdefgh1234", "legacy key")
    expect(isFullKey(legacy.order?.apiKey) == "sk-monk-abcdefgh1234", "legacy full")
    expect(legacy.order?.dailyLimit == 30 && legacy.order?.fairness?.hourMax == 60, "legacy caps still decode")

    expect(isFullKey("  Bearer sk-monk-abcdefgh1234 ") == "sk-monk-abcdefgh1234", "bearer strip")
    expect(isFullKey("sk-monk-••••abcd") == nil, "mask is not a key")
    expect(isFullKey("monk-abcdefgh1234") == "monk-abcdefgh1234", "legacy prefix")
    expect(isFullKey("sk-other-abcdefgh") == nil, "foreign prefix")
    expect(maskedKey("sk-monk-abcdefgh1234") == "sk-monk-…1234", "mask full")
    expect(maskedKey("sk-monk-••••abcd") == "sk-monk-••••abcd", "mask keep server")
    expect(maskedKey(nil) == "sk-monk-••••", "mask nil")

    expect(lookupFailureMessage(status: 404, error: "No matching order.") == "未查到该邮箱的已支付订单。", "404 zh")
    expect(lookupFailureMessage(status: 429, error: nil).contains("频繁"), "429 zh")

    expect(MonkCatalog.options.map(\.name) == ["monk", "monk-fast", "monk-coding", "monk-free"], "models")
    expect(MonkCatalog.baseURL == "https://monk.party/v1", "base url")
    expect(MonkLimits.daily == 200 && MonkLimits.hourMax == 800 && MonkLimits.sixHourMax == 2_400, "published call caps")
    expect(MonkLimits.hourPrompt == 60_000_000 && MonkLimits.sixHourPrompt == 90_000_000, "published token caps")

    let link = Cfg.accountURL(email: "you@example.com", tradeNo: "MK123")
    expect(link.host == "monk.party", "acct host")
    expect(link.path.hasPrefix("/account"), "acct path")
    expect(link.query?.contains("trade=MK123") == true, "acct trade")
    expect(link.query?.contains("email=") == true, "acct email")

    expect(AppMeta.version == "1.6.0", "app version")
    expect(UpdateChecker.isNewer(latest: "v1.6.0", current: "1.5.0"), "semver newer")
    expect(!UpdateChecker.isNewer(latest: "1.6.0", current: "1.6.0"), "semver same")
    expect(!UpdateChecker.isNewer(latest: "v1.5.0", current: "1.6.0"), "semver older")

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
