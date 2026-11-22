import SwiftUI
import SwiftData
import UIKit

/// 添加 / 编辑一件产品。
///
/// 新增（目标 10 秒）：
/// 1. 全屏相机 + 取景框（或相册 / 不拍照手动添加）
/// 2. "浮起来"：主体从照片背景里升起，同时识别 EXP、开封后保质期、容量、名称
/// 3. 一张确认卡：名称已填好并聚焦，识别到的胶囊可点改，「放上妆台」
///
/// 编辑：直接是同一张确认卡（全部展开），可以重新拍照 / 重新抠图，调整剩余量。
struct ProductEditorView: View {
    let target: EditorTarget

    enum Stage: Equatable { case camera, lifting, confirm }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var subjectSpace

    @State private var d: ProductDraft
    @State private var stage: Stage
    /// 方向已归正的照片（内存里，用来显示和重新抠图）
    @State private var photoImage: UIImage? = nil
    @State private var cutout: ProductCutout? = nil
    @State private var cutoutImage: UIImage? = nil
    @State private var lifted = false
    @State private var analyzing = false
    @State private var liftTick = 0
    @State private var recutTick = 0
    @State private var isRecutting = false
    @State private var recutStatus: String? = nil
    /// 从确认卡点「重新拍照」进来的：关掉相机回到确认卡，而不是关掉整个表单
    @State private var cameraFromConfirm = false
    @State private var work: Task<Void, Never>? = nil

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _d = State(initialValue: ProductDraft())
            _stage = State(initialValue: .camera)
            _photoImage = State(initialValue: nil)
            _cutoutImage = State(initialValue: nil)
        case .edit(let p):
            _d = State(initialValue: ProductDraft(product: p))
            _stage = State(initialValue: .confirm)
            _photoImage = State(initialValue: p.photo.flatMap { UIImage(data: $0) })
            _cutoutImage = State(initialValue: p.cutout.flatMap { UIImage(data: $0) })
        }
    }

    /// 便捷入口：nil = 新增
    init(product: Product?) {
        self.init(target: product.map { EditorTarget.edit($0) } ?? .new)
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var motion: Animation { reduceMotion ? EditorMotion.fade : EditorMotion.spring }

    var body: some View {
        NavigationStack {
            ZStack {
                switch stage {
                case .camera:
                    CaptureCameraView(
                        onCapture: { image, crop in startAnalysis(image, crop: crop) },
                        onLibrary: { image in startAnalysis(image, crop: nil) },
                        onManual: manualAdd,
                        onClose: closeCamera,
                        closeTitle: cameraFromConfirm ? "返回" : "取消")
                    .transition(.opacity)

                case .lifting:
                    LiftingStageView(photo: photoImage, cutout: cutout, lifted: lifted, analyzing: analyzing,
                                     namespace: subjectSpace)
                    .transition(.opacity)

                case .confirm:
                    ProductConfirmCard(
                        d: $d,
                        isEditing: isEditing,
                        photoImage: photoImage,
                        cutoutImage: cutoutImage,
                        namespace: subjectSpace,
                        matchEnabled: true,
                        recutStatus: recutStatus,
                        isRecutting: isRecutting,
                        onRetake: retake,
                        onRecut: recut,
                        onUseOriginal: useOriginal,
                        onSave: save)
                    .transition(.opacity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(stage == .camera ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if stage != .camera {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(stage == .camera ? .hidden : .visible)
        .presentationBackground(stage == .camera ? Color.black : Color(uiColor: .systemGroupedBackground))
        .interactiveDismissDisabled(stage == .lifting)
        .sensoryFeedback(.impact(weight: .medium), trigger: liftTick)
        .sensoryFeedback(.selection, trigger: recutTick)
        .onDisappear { work?.cancel() }
    }

    private var title: String {
        switch stage {
        case .camera: return ""
        case .lifting: return "识别中"
        case .confirm: return isEditing ? "编辑" : "确认一下"
        }
    }

    // MARK: 第 1 → 2 步：拍到照片，开始抠图 + 识别

    private func startAnalysis(_ raw: UIImage, crop: CGRect?) {
        work?.cancel()
        lifted = false
        analyzing = true
        cutout = nil
        cutoutImage = nil
        recutStatus = nil
        photoImage = nil
        withAnimation(motion) { stage = .lifting }

        let overwrite = !isEditing
        work = Task { @MainActor in
            let prepared = await Task.detached(priority: .userInitiated) { () -> UIImage in
                let up = ImageTools.normalized(raw, maxSide: 2400)
                guard let crop else { return up }
                return ImageTools.crop(up, normalizedRect: crop)
            }.value
            guard !Task.isCancelled else { return }
            photoImage = prepared

            let a = await CaptureService.analyze(prepared)
            guard !Task.isCancelled else { return }
            let jpeg = await Task.detached(priority: .userInitiated) { ImageTools.photoJPEG(a.photo) }.value
            guard !Task.isCancelled else { return }

            d.apply(a, overwrite: overwrite)
            d.photo = jpeg
            d.cutout = a.cutout?.png
            photoImage = a.photo
            analyzing = false
            announce(a)

            if let c = a.cutout {
                // 先把抠图原位叠在照片上（看不出区别），下一帧再让它浮起来
                cutout = c
                cutoutImage = c.image
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(reduceMotion ? EditorMotion.fade : EditorMotion.lift) { lifted = true }
                liftTick += 1
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1100))
            } else {
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            withAnimation(motion) { stage = .confirm }
        }
    }

    private func announce(_ a: CaptureAnalysis) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        var parts: [String] = [a.cutout != nil ? "已抠出产品" : "没找到清楚的主体，使用整张照片"]
        if let e = a.reading.expiry { parts.append("到期 \(e.text)") }
        if let m = a.reading.pao { parts.append("开封后 \(m) 个月") }
        if let c = a.reading.capacity, let u = a.reading.unit { parts.append("\(EditorFmt.amount(c)) \(u)") }
        if let n = a.reading.name { parts.append("名称 \(n)") }
        UIAccessibility.post(notification: .announcement, argument: parts.joined(separator: "，"))
    }

    // MARK: 其他路径

    private func manualAdd() {
        withAnimation(motion) { stage = .confirm }
    }

    private func closeCamera() {
        if cameraFromConfirm {
            withAnimation(motion) { stage = .confirm }
        } else {
            dismiss()
        }
    }

    private func retake() {
        cameraFromConfirm = true
        withAnimation(motion) { stage = .camera }
    }

    /// 重新抠图：在"全部主体 / 第 1 个 / 第 2 个…"之间轮换
    private func recut() {
        guard let photo = photoImage ?? d.photo.flatMap({ UIImage(data: $0) }) else { return }
        let next: Int
        if let cutout { next = cutout.variant + 1 } else { next = cutoutImage == nil ? 0 : 1 }
        isRecutting = true
        recutStatus = nil
        work?.cancel()
        work = Task { @MainActor in
            let c = await CaptureService.cutout(from: photo, variant: next)
            guard !Task.isCancelled else { return }
            isRecutting = false
            if let c {
                withAnimation(motion) {
                    cutout = c
                    cutoutImage = c.image
                    d.cutout = c.png
                }
                recutTick += 1
                if c.instanceCount <= 1 {
                    recutStatus = "照片里只找到一个主体"
                } else if c.variant == 0 {
                    recutStatus = "全部 \(c.instanceCount) 个主体"
                } else {
                    recutStatus = "第 \(c.variant) 个，共 \(c.instanceCount) 个主体"
                }
            } else {
                recutStatus = "没找到能抠出来的主体，先用原图"
            }
        }
    }

    private func useOriginal() {
        withAnimation(motion) {
            cutout = nil
            cutoutImage = nil
            d.cutout = nil
        }
        recutStatus = nil
    }

    // MARK: 保存

    private func save() {
        guard !d.trimmedName.isEmpty else { return }
        switch target {
        case .new:
            let product = Product(name: d.trimmedName, kind: d.kind, expiryDate: d.expValue)
            d.write(to: product)
            withAnimation(EditorMotion.spring) { context.insert(product) }
        case .edit(let product):
            d.write(to: product)
        }
        dismiss()
    }
}
