import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - 相机会话

/// 一个只拍静态照片的后置相机。会话的配置 / 启停都在自己的串行队列上。
final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable { case idle, running, denied, unavailable }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "BeautyShelf.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var completion: ((UIImage?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.run() } else { self?.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured && !self.configure() {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    /// 在 queue 上调用
    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        self.device = device
        configured = true
        return true
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard status == .running, !isCapturing else { return }
        isCapturing = true
        completion = done
        queue.async { [weak self] in
            guard let self else { return }
            // 竖着拍：照片像素方向跟屏幕一致
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(90) {
                c.videoRotationAngle = 90
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// 点按对焦（devicePoint 为 0...1 的传感器坐标）
    func focus(at devicePoint: CGPoint) {
        queue.async { [weak self] in
            guard let device = self?.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap { UIImage(data: $0) } : nil
        DispatchQueue.main.async {
            self.isCapturing = false
            let done = self.completion
            self.completion = nil
            done?(image)
        }
    }
}

// MARK: - 预览层

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void = { _, _ in }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint, CGPoint) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90), c.videoRotationAngle != 90 {
                c.videoRotationAngle = 90
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            let p = g.location(in: self)
            onTap?(p, previewLayer.captureDevicePointConverted(fromLayerPoint: p))
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.onTap = onTap
        v.addGestureRecognizer(UITapGestureRecognizer(target: v, action: #selector(PreviewView.handleTap(_:))))
        v.isAccessibilityElement = false
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onTap = onTap
    }
}

// MARK: - 第 1 步：全屏拍照

/// 全屏相机 + 取景框。拍到的照片会裁到取景框（外扩一点）再交出去。
struct CaptureCameraView: View {
    /// 拍照：照片 + 取景框对应的裁切区域（归一化、左上角原点；照片须先归正方向）
    var onCapture: (UIImage, CGRect?) -> Void
    var onLibrary: (UIImage) -> Void
    var onManual: () -> Void
    var onClose: () -> Void
    var closeTitle: String = "取消"

    @StateObject private var camera = CameraController()
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var shutterCount = 0
    @State private var focusPoint: CGPoint? = nil
    @State private var focusTick = 0
    @State private var loadingLibrary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// 全屏（忽略安全区）的尺寸，取景框和预览都在这个坐标系里
    @State private var screenSize: CGSize = .zero

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let guide = Self.guideRect(in: geo.size)
                ZStack {
                    Color.black

                    if camera.status == .running || camera.status == .idle {
                        CameraPreview(session: camera.session) { layerPoint, devicePoint in
                            camera.focus(at: devicePoint)
                            focusPoint = layerPoint
                            focusTick += 1
                        }
                        .accessibilityHidden(true)
                    }

                    frameMask(guide: guide, size: geo.size)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    if let p = focusPoint {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.yellow, lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                            .position(p)
                            .id(focusTick)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    statusMessage
                        .frame(width: max(120, guide.width - 32))
                        .position(x: guide.midX, y: guide.midY)

                    hint
                        .frame(maxWidth: max(120, geo.size.width - 48))
                        .position(x: geo.size.width / 2, y: max(120, guide.minY - 44))
                }
                .onAppear { screenSize = geo.size }
                .onChange(of: geo.size) { _, new in screenSize = new }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in loadLibrary(item) }
        .onChange(of: focusTick) {
            let tick = focusTick
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if tick == focusTick { withAnimation(EditorMotion.fade) { focusPoint = nil } }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: shutterCount)
    }

    // MARK: 取景框

    /// 竖向的取景框：宽 72%（最多 340），高 = 宽 × 1.3，略偏上
    static func guideRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.72, 340)
        let h = min(w * 1.3, size.height * 0.55)
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.44 - h / 2, width: w, height: h)
    }

    /// 取景框在照片上的位置（预览是 aspectFill 铺满，所以要先算出照片在屏幕上的显示范围）
    static func cropRect(guide: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let s = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let dw = imageSize.width * s, dh = imageSize.height * s
        let ox = (viewSize.width - dw) / 2, oy = (viewSize.height - dh) / 2
        // 外扩 15%，产品稍微出框也不会被切
        let g = guide.insetBy(dx: -guide.width * 0.15, dy: -guide.height * 0.15)
        return CGRect(x: (g.minX - ox) / dw, y: (g.minY - oy) / dh, width: g.width / dw, height: g.height / dh)
    }

    private func frameMask(guide: CGRect, size: CGSize) -> some View {
        ZStack {
            // 框外压暗
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: guide, cornerSize: CGSize(width: 28, height: 28), style: .continuous)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .frame(width: guide.width, height: guide.height)
                .position(x: guide.midX, y: guide.midY)
        }
    }

    private var hint: some View {
        VStack(spacing: 4) {
            Text("把产品放进框里")
                .font(.headline)
            Text("正面朝上；拍到 EXP 和开罐图标，日期会自动填好")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch camera.status {
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("需要相机权限才能拍照").font(.headline)
                Text("也可以从相册选一张，或者不拍照直接添加。")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
                Button("去设置里打开") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
        case .unavailable:
            VStack(spacing: 8) {
                Image(systemName: "camera.badge.ellipsis").font(.largeTitle)
                Text("这台设备不能拍照").font(.headline)
                Text("从相册选一张，或者不拍照直接添加。")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
        case .idle, .running:
            if loadingLibrary {
                ProgressView().tint(.white).controlSize(.large)
                    .accessibilityLabel("正在读取照片")
            }
        }
    }

    // MARK: 按钮

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Text(closeTitle)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle").font(.title2)
                        Text("相册").font(.caption)
                    }
                    .frame(minWidth: 64, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("从相册选照片")

                Spacer()

                Button {
                    shoot()
                } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 66, height: 66)
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 80, height: 80)
                        if camera.isCapturing {
                            ProgressView().tint(.black)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .contentShape(Circle())
                }
                .buttonStyle(ShutterStyle(reduceMotion: reduceMotion))
                .disabled(camera.status != .running || camera.isCapturing)
                .opacity(camera.status == .running ? 1 : 0.35)
                .accessibilityLabel("拍照")
                .accessibilityHint("拍下框里的产品，自动抠图并识别日期和容量")

                Spacer()

                // 与左边对称的占位，让快门居中
                Color.clear.frame(width: 64, height: 56)
            }

            Button(action: onManual) {
                Text("不拍照，手动添加")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func shoot() {
        shutterCount += 1
        let size = screenSize
        let guide = Self.guideRect(in: size)
        camera.capture { image in
            guard let image else { return }
            onCapture(image, Self.cropRect(guide: guide, viewSize: size, imageSize: image.size))
        }
    }

    private func loadLibrary(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingLibrary = true
        Task { @MainActor in
            defer {
                loadingLibrary = false
                pickerItem = nil
            }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                onLibrary(image)
            }
        }
    }
}

private struct ShutterStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(EditorMotion.snappy, value: configuration.isPressed)
    }
}
