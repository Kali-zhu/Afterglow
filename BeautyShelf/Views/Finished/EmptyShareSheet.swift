import SwiftUI
import SwiftData
import Photos

/// 「分享空瓶」：拿一条用空的记录，直接把卡片排出来 → 保存到相册，或调起系统分享。
/// 预览和导出的图来自同一个 `EmptyShareCardView`，看到什么就存下什么。
/// 用后感和复购态度在这张表里写（写回这条记录），卡片跟着变。
struct EmptyShareSheet: View {
    let product: Product

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 全部记录：个人空瓶序号要按整面墙来数
    @Query private var all: [Product]

    @State private var note: String
    @State private var stance: RepurchaseStance?
    @State private var image: UIImage? = nil
    @State private var fileURL: URL? = nil
    /// 保存到相册的提示（成功 / 没有权限 / 失败）
    @State private var saveNote: String? = nil
    @State private var isSaving = false
    @State private var savedTick = 0

    init(product: Product) {
        self.product = product
        _note = State(initialValue: product.note)
        _stance = State(initialValue: product.repurchase)
    }

    /// 卡片依赖的东西变了就重画一遍
    private var renderKey: String {
        [product.uid.uuidString, product.name, "\(product.useCount)",
         "\(product.finishedDate?.timeIntervalSince1970 ?? 0)",
         note, stance?.rawValue ?? "-"].joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    editor
                    actions
                }
                .padding(20)
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("分享空瓶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .task(id: renderKey) { await render() }
        .sensoryFeedback(.success, trigger: savedTick)
        .onDisappear { coordinator.dataChanged() }
    }

    // MARK: 预览

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.card)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                    .transition(.opacity)
                    .accessibilityLabel("「\(product.name)」的空瓶分享卡预览")
            } else {
                ProgressView()
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: 420)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: image)
    }

    // MARK: 写下心得与复购态度
    //
    // 写的时候同时写回这条记录：卡片排的就是记录本身，所以预览、导出和记录永远是同一个内容。

    private var noteBinding: Binding<String> {
        Binding(get: { note },
                set: { text in
                    note = text
                    product.note = text
                    coordinator.dataChanged()
                })
    }

    private func setStance(_ value: RepurchaseStance?) {
        stance = value
        product.repurchase = value
        coordinator.dataChanged()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("用后感")
                    .font(.subheadline.weight(.semibold))
                TextField("写两句，会印在卡片上", text: noteBinding, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                    .accessibilityLabel("用后感")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("复购态度")
                    .font(.subheadline.weight(.semibold))
                FlowLayout(spacing: 8) {
                    ForEach(RepurchaseStance.allCases) { s in
                        ChoiceChip(title: s.title, isOn: stance == s) {
                            withAnimation(Theme.snappy) { setStance(stance == s ? nil : s) }
                        }
                        .accessibilityHint(stance == s ? "再点一次取消，卡片上不盖印章" : "盖在卡片上的印章")
                    }
                }
                Text(stance == nil ? "没选就不盖印章。" : "再点一次可以取消。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.card)
        }
    }

    // MARK: 保存 / 分享

    @ViewBuilder
    private var actions: some View {
        if let image, let fileURL {
            VStack(spacing: 10) {
                Button { save(image) } label: {
                    Label(isSaving ? "正在保存…" : "保存到相册", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .disabled(isSaving)

                ShareLink(item: fileURL,
                          preview: SharePreview("\(product.name) 空瓶", image: Image(uiImage: image))) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Text(saveNote ?? "1080 × 1440，3:4 竖图。图里只有这张卡片，没有页面上的按钮。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    // MARK: 渲染

    @MainActor
    private func render() async {
        // 让出一帧，先把刚改的字画到输入框里
        await Task.yield()
        guard let rendered = EmptyShareCard.render(
            product: product,
            sequence: EmptyShareCard.sequence(of: product, among: all)
        ) else { return }
        image = rendered
        fileURL = EmptyShareCard.writePNG(rendered, product: product)
    }

    /// 存到相册：只要"添加"权限，不读用户已有的照片
    private func save(_ image: UIImage) {
        guard !isSaving else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    isSaving = false
                    saveNote = "没有相册权限，可以改用「分享」保存。"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    isSaving = false
                    if success {
                        saveNote = "已存到相册。"
                        savedTick += 1
                    } else {
                        saveNote = "没存上，可以改用「分享」保存。"
                    }
                }
            }
        }
    }
}
