import SwiftUI
import UIKit
import Darwin

struct ScreenOffView: View {
    @State private var message: String = "正在尝试息屏锁屏…"
    @State private var detail: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
            Text(message)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .task { attemptLock() }
    }

    private func attemptLock() {
        var lines: [String] = []

        // 尝试 1：GraphicsServices 私有事件 GSEventLockDevice（历史行为等价于按电源键：息屏+锁定）
        let gsPath = "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices"
        if let lockDevice = Self.loadCFunction(gsPath, "GSEventLockDevice") {
            lockDevice()
            lines.append("① GSEventLockDevice 已调用")
        } else {
            lines.append("① GSEventLockDevice 符号未找到")
        }

        // 尝试 2：BackBoardServices 私有熄屏接口
        let bksPath = "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices"
        if let setBlanked = Self.loadBoolFunction(bksPath, "BKSDisplaySetScreenBlanked") {
            setBlanked(true)
            lines.append("② BKSDisplaySetScreenBlanked 已调用")
        } else {
            lines.append("② BKSDisplaySetScreenBlanked 符号未找到")
        }

        detail = lines.joined(separator: "\n")

        // 2 秒后仍处于激活状态 → 私有接口未生效
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard UIApplication.shared.applicationState == .active else { return }
            message = "接口未生效（此路不通）"
            detail = lines.joined(separator: "\n") + "\n\n即将退回后台，交给系统自动锁定"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                Self.suspendApp()
            }
        }
    }

    private static func loadCFunction(_ path: String, _ symbol: String) -> (@convention(c) () -> Void)? {
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) () -> Void).self)
    }

    private static func loadBoolFunction(_ path: String, _ symbol: String) -> (@convention(c) (Bool) -> Void)? {
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (Bool) -> Void).self)
    }

    private static func suspendApp() {
        let sel = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: sel) {
            _ = UIApplication.shared.perform(sel)
        }
    }
}
