import Foundation
import SwiftData
import SwiftUI

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case skincare = "护肤", makeup = "彩妆", fragrance = "香氛", body = "身体", hair = "头发"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .skincare: "drop.fill"
        case .makeup: "paintbrush.pointed.fill"
        case .fragrance: "sparkles"
        case .body: "hands.sparkles.fill"
        case .hair: "wind"
        }
    }
}

@Model
final class Product {
    var name: String
    var brand: String
    var categoryRaw: String
    var totalAmount: Double       // 总量，例如 50 (ml / g)
    var remainingAmount: Double   // 剩余量
    var unit: String
    var amountPerUse: Double      // 每次大约用量
    var useCount: Int
    var openedDate: Date?
    var expiryDate: Date
    var tintHex: String
    var createdAt: Date

    init(name: String, brand: String, category: ProductCategory, totalAmount: Double,
         unit: String = "ml", amountPerUse: Double = 1, expiryDate: Date,
         openedDate: Date? = nil, tintHex: String = "E7B873") {
        self.name = name; self.brand = brand; self.categoryRaw = category.rawValue
        self.totalAmount = totalAmount; self.remainingAmount = totalAmount
        self.unit = unit; self.amountPerUse = amountPerUse; self.useCount = 0
        self.openedDate = openedDate; self.expiryDate = expiryDate
        self.tintHex = tintHex; self.createdAt = .now
    }

    var category: ProductCategory { ProductCategory(rawValue: categoryRaw) ?? .skincare }
    var level: Double { totalAmount > 0 ? max(0, min(1, remainingAmount / totalAmount)) : 0 }
    var tint: Color { Color(hex: tintHex) }
    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                         to: Calendar.current.startOfDay(for: expiryDate)).day ?? 0
    }
    var expiryState: ExpiryState {
        switch daysUntilExpiry {
        case ..<0: .expired
        case 0...30: .soon
        default: .fresh
        }
    }

    var expiryText: String {
        daysUntilExpiry >= 0 ? "\(daysUntilExpiry) 天后过期" : "已过期 \(-daysUntilExpiry) 天"
    }

    func logUse() {
        useCount += 1
        remainingAmount = max(0, remainingAmount - amountPerUse)
        if openedDate == nil { openedDate = .now }
    }
}

enum ExpiryState {
    case fresh, soon, expired
    var color: Color {
        switch self { case .fresh: Theme.sage; case .soon: Theme.honey; case .expired: Theme.rouge }
    }
}
