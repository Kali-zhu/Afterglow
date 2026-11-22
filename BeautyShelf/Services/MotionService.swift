import CoreMotion
import UIKit

/// 液面物理的传感器来源：CMMotionManager deviceMotion，60 Hz，把重力 x / y 写进 `LiquidMotionSource`。
/// - 按需开启：妆台 / 详情出现时 `begin()`，消失时 `end()`（引用计数）
/// - App 不活跃（进入后台、控制中心下拉）时停止
/// - 开启"减弱动态效果"时不开启，液面保持水平
/// 重力值不走 SwiftUI 的观察机制（避免 60 Hz 让整棵视图树失效），容器在自己的 TimelineView 帧里读取。
final class MotionService {
    static let shared = MotionService()

    private let manager = CMMotionManager()
    private var demand = 0
    private var appActive = true
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appActive = true
            self?.update()
        })
        tokens.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appActive = false
            self?.update()
        })
        tokens.append(nc.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        })
    }

    /// 有一个需要液面物理的界面出现了
    func begin() {
        demand += 1
        update()
    }

    /// 那个界面消失了
    func end() {
        demand = max(0, demand - 1)
        update()
    }

    private var shouldRun: Bool {
        demand > 0 && appActive && !UIAccessibility.isReduceMotionEnabled && manager.isDeviceMotionAvailable
    }

    private func update() {
        let source = LiquidMotionSource.shared
        if shouldRun {
            guard !manager.isDeviceMotionActive else { return }
            manager.deviceMotionUpdateInterval = 1.0 / 60
            manager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let g = motion?.gravity else { return }
                source.gravity = CGVector(dx: g.x, dy: g.y)
                source.isActive = true
            }
        } else {
            if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
            source.isActive = false
            source.gravity = CGVector(dx: 0, dy: -1)
        }
    }
}
