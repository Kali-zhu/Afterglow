import SwiftUI

/// 「生成空瓶记」：选按月 / 按年和具体时段 → 预览分享图 → ShareLink（存相册、发小红书）
struct EmptiesShareSheet: View {
    let finished: [Product]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monthly = true
    @State private var period: EmptiesPeriod? = nil
    @State private var image: UIImage? = nil
    @State private var fileURL: URL? = nil

    private var periods: [EmptiesPeriod] { EmptiesPeriod.available(in: finished, monthly: monthly) }

    private var count: Int {
        guard let period else { return 0 }
        return ShareCard.items(for: period, in: finished).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("范围", selection: $monthly) {
                        Text("按月").tag(true)
                        Text("按年").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !periods.isEmpty {
                        HStack {
                            Text(monthly ? "月份" : "年份")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker(monthly ? "月份" : "年份", selection: $period) {
                                ForEach(periods) { p in
                                    Text(p.pickerTitle).tag(Optional(p))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .frame(minHeight: 44)
                    }

                    preview

                    if let fileURL, let image, let period {
                        ShareLink(item: fileURL,
                                  preview: SharePreview("\(period.title) · \(count) 件", image: Image(uiImage: image))) {
                            Label("分享 / 存到相册", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.primary)
                        .foregroundStyle(Color(uiColor: .systemBackground))

                        Text("1080 × 1440，3:4 竖图，发小红书刚好。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("空瓶记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .onAppear { if period == nil { period = periods.first } }
        .onChange(of: monthly) { _, isMonthly in
            // 切换按月 / 按年时，尽量停在同一段时间里
            if let current = period, let d = finished.compactMap(\.finishedDate).first(where: current.contains) {
                let next = EmptiesPeriod.of(d, monthly: isMonthly)
                period = periods.contains(next) ? next : periods.first
            } else {
                period = periods.first
            }
        }
        .task(id: period) { await render() }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.opacity)
                    .accessibilityLabel(period.map { "\($0.title) \(count) 件的分享图预览" } ?? "分享图预览")
            } else if periods.isEmpty {
                Text("还没有空瓶").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: 420)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: image)
    }

    @MainActor
    private func render() async {
        guard let period else {
            image = nil
            fileURL = nil
            return
        }
        // 让出一帧，先把选择器的变化画出来
        await Task.yield()
        guard let rendered = ShareCard.render(period: period, products: finished) else { return }
        image = rendered
        fileURL = ShareCard.writePNG(rendered, period: period)
    }
}
