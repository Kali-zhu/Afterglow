import SwiftUI

struct AddProductView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var category: ProductCategory = .skincare
    @State private var total = 50.0
    @State private var unit = "ml"
    @State private var perUse = 1.0
    @State private var expiry = Calendar.current.date(byAdding: .month, value: 12, to: .now)!
    @State private var tint = Theme.liquids[0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称，例如 小棕瓶精华", text: $name)
                    TextField("品牌", text: $brand)
                    Picker("分类", selection: $category) {
                        ForEach(ProductCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("容量") {
                    Stepper(value: $total, in: 1...1000, step: 5) { Text("总量 \(Int(total)) \(unit)") }
                    Picker("单位", selection: $unit) { ForEach(["ml", "g", "片", "支"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented)
                    Stepper(value: $perUse, in: 0.5...20, step: 0.5) {
                        Text("每次约 \(perUse, specifier: "%.1f") \(unit)")
                    }
                }
                Section("保质期") {
                    DatePicker("到期日", selection: $expiry, displayedComponents: .date)
                }
                Section("液体颜色") {
                    HStack {
                        ForEach(Theme.liquids, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: tint == hex ? 2 : 0))
                                .scaleEffect(tint == hex ? 1.15 : 1)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Circle())
                                .onTapGesture { withAnimation(Theme.snappy) { tint = hex } }
                        }
                    }
                }
            }
            .navigationTitle("添加产品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        context.insert(Product(name: name, brand: brand, category: category,
                                               totalAmount: total, unit: unit, amountPerUse: perUse,
                                               expiryDate: expiry, tintHex: tint))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
            }
}
