import SwiftUI
import UIKit

enum OpenedChoice: Hashable { case notYet, today, custom }
enum ExpChoice: Hashable { case years(Int), custom }

enum PerUseLevel: CaseIterable, Hashable {
    case small, medium, large
    var title: String {
        switch self {
        case .small: "少量"
        case .medium: "适中"
        case .large: "多"
        }
    }
    private var factor: Double {
        switch self {
        case .small: 0.01
        case .medium: 0.02
        case .large: 0.04
        }
    }
    /// 按容量自动换算，保留一位小数
    func amount(total: Double) -> Double {
        max(0.1, (total * factor * 10).rounded() / 10)
    }
}

/// 编辑器里正在编辑的值。所有联动（换形状、换容量）都走这里的方法，不靠 onChange 链。
struct ProductDraft {
    var name = ""
    var brand = ""
    var category: ProductCategory = .skincare
    var kind: VesselKind = .bottle
    var total: Double = 50
    var remaining: Double = 50
    var remainingTouched = false
    var unit = "ml"
    /// 用户填过 / 识别到容量（胶囊不再显示为"待填"）
    var capacityTouched = false
    var perUse: Double = 1
    var perUseLevel: PerUseLevel? = .medium
    var opened: OpenedChoice = .notYet
    var openedDate = Date.now
    var pao: Int? = 6
    var paoTouched = false
    var exp: ExpChoice = .years(2)
    var expDate = Date.now
    var expTouched = false
    var priceText = ""
    var backup = 0
    var tint = "E7B873"
    var tintTouched = false
    var morning = false
    var evening = false
    var makeup: Bool? = nil
    var photo: Data? = nil
    var cutout: Data? = nil
    var cap: CapStyle = .screw
    var capTouched = false
    var finish: GlassFinish = .clear
    var finishTouched = false

    // 识别结果（决定胶囊是"识别到的"还是"待填"）
    var detectedExpiry: LabelDate? = nil
    var detectedPAO = false
    var detectedCapacity = false
    /// 自动填进去的名称 / 品牌；用户改过之后就不再被新照片覆盖
    var autoName: String? = nil
    var autoBrand: String? = nil

    init() {
        pao = kind.suggestedPAO(for: category)
        tint = kind.defaultTint
    }

    init(product p: Product) {
        name = p.name
        brand = p.brand
        category = p.category
        kind = p.kind
        total = p.totalAmount
        remaining = p.remainingAmount
        remainingTouched = true
        unit = p.unit
        capacityTouched = true
        perUse = p.amountPerUse
        perUseLevel = PerUseLevel.allCases.first { abs($0.amount(total: p.totalAmount) - p.amountPerUse) < 0.001 }
        if let o = p.openedDate {
            opened = Calendar.current.isDateInToday(o) ? .today : .custom
            openedDate = o
        } else {
            opened = .notYet
        }
        pao = p.paoMonths
        paoTouched = true
        exp = .custom
        expDate = p.expiryDate
        expTouched = true
        if let price = p.price { priceText = EditorFmt.amount(price) }
        backup = p.backupStock
        tint = p.tintHex
        tintTouched = true
        morning = p.inMorning
        evening = p.inEvening
        makeup = p.inMakeup
        photo = p.photo
        cutout = p.cutout
        cap = p.capStyle
        capTouched = true
        finish = p.finish
        finishTouched = true
    }

    var mode: MeasureMode { kind.measureMode }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: 日期

    var openedValue: Date? {
        switch opened {
        case .notYet: return nil
        case .today, .custom: return openedDate
        }
    }

    var expValue: Date {
        switch exp {
        case .years(let n):
            let cal = Calendar.current
            return cal.date(byAdding: .year, value: n, to: cal.startOfDay(for: .now)) ?? .now
        case .custom:
            return expDate
        }
    }

    // MARK: 联动

    mutating func changeKind(to new: VesselKind, isEditing: Bool) {
        let old = kind
        guard old != new else { return }
        kind = new
        let fraction = total > 0 ? min(1, remaining / total) : 1
        if !isEditing || old.measureMode != new.measureMode {
            // 识别到 / 填过的容量在同一计量方式下保留（罐的默认单位是 g，其余 ml）
            let keepCapacity = capacityTouched && old.measureMode == new.measureMode
            if !keepCapacity {
                unit = new.defaultUnit
                total = new.defaultTotal
                capacityTouched = false
                detectedCapacity = false
            }
            if remainingTouched {
                let r = total * fraction
                remaining = new.measureMode == .volume ? r : r.rounded()
            } else {
                remaining = total
            }
        }
        if let level = perUseLevel { perUse = level.amount(total: total) }
        if !paoTouched { pao = new.suggestedPAO(for: category) }
        if !tintTouched { tint = new.defaultTint }
    }

    mutating func changeCategory(to c: ProductCategory) {
        category = c
        if !paoTouched { pao = kind.suggestedPAO(for: c) }
    }

    mutating func changeTotal(_ t: Double) {
        total = t
        if remainingTouched {
            remaining = min(remaining, t)
        } else {
            remaining = t
        }
        if let level = perUseLevel { perUse = level.amount(total: t) }
    }

    // MARK: 识别结果写进表单

    /// `overwrite == false`（编辑已有产品时）只换照片，不动用户已有的数据。
    mutating func apply(_ a: CaptureAnalysis, overwrite: Bool) {
        let r = a.reading
        guard overwrite else { return }

        if let c = a.category { changeCategory(to: c) }
        changeKind(to: a.kind, isEditing: false)

        if let cap = r.capacity, let u = r.unit {
            if u == "片" {
                if kind != .sheet { changeKind(to: .sheet, isEditing: false) }
                unit = "片"
                changeTotal(cap.rounded())
                detectedCapacity = true
                capacityTouched = true
            } else if kind.measureMode == .volume {
                unit = u
                changeTotal(cap)
                detectedCapacity = true
                capacityTouched = true
            }
        } else {
            detectedCapacity = false
        }

        if let m = r.pao {
            pao = m
            paoTouched = true
            detectedPAO = true
        } else {
            detectedPAO = false
        }

        if let e = r.expiry, let date = e.date {
            exp = .custom
            expDate = date
            expTouched = true
            detectedExpiry = e
        } else {
            detectedExpiry = nil
        }

        if let n = r.name, name.isEmpty || name == autoName {
            name = n
            autoName = n
        }
        if let b = r.brand, brand.isEmpty || brand == autoBrand {
            brand = b
            autoBrand = b
        }
        if let hex = a.tintHex, !tintTouched { tint = hex }
    }

    // MARK: 写回模型

    var parsedPrice: Double? {
        let s = priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let v = Double(s), v > 0 else { return nil }
        return v
    }

    func write(to product: Product) {
        product.name = trimmedName
        product.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        product.category = category
        product.kind = kind
        switch mode {
        case .volume:
            product.totalAmount = total
            product.unit = unit
            product.amountPerUse = perUse
        case .count:
            product.totalAmount = total.rounded()
            product.unit = "片"
            product.amountPerUse = 1
        case .estimate:
            product.totalAmount = 100
            product.unit = "%"
            product.amountPerUse = 0
        }
        product.remainingAmount = min(max(0, remaining), product.totalAmount)
        product.openedDate = openedValue
        product.paoMonths = pao
        product.expiryDate = expValue
        product.price = parsedPrice
        product.backupStock = backup
        product.tintHex = tint
        product.inMorning = morning
        product.inEvening = evening
        product.inMakeup = makeup
        product.photo = photo
        product.cutout = cutout
        product.capStyle = capTouched ? cap : CaptureService.defaultCap(kind: kind, category: category, name: trimmedName)
        product.finish = finishTouched ? finish : CaptureService.defaultFinish(kind: kind, category: category)
        if product.level >= 0.15 { product.lowStockAlertAt = nil }
    }

    /// 没改过盖子 / 材质时，"更多"里显示的默认值
    var effectiveCap: CapStyle { capTouched ? cap : CaptureService.defaultCap(kind: kind, category: category, name: trimmedName) }
    var effectiveFinish: GlassFinish { finishTouched ? finish : CaptureService.defaultFinish(kind: kind, category: category) }
}

/// 编辑器自己的格式化（不依赖其他模块的改版）
enum EditorFmt {
    static func amount(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r == r.rounded() { return "\(Int(r))" }
        return String(format: "%.1f", r)
    }

    /// 2027年5月21日
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
    }

    /// 2027年5月
    static func month(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }
}

/// 编辑器里的动效（减弱动态效果时由调用方换成淡入淡出）
enum EditorMotion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let lift = Animation.spring(response: 0.55, dampingFraction: 0.68)
    static let fade = Animation.easeInOut(duration: 0.22)
}
