import Foundation
import CallKit
import UIKit
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "CallTracker")

/// 通过 CXCallObserver 实时观察系统通话，校验“点击拨号”后是否真的拨出/接通。
/// 说明：iOS 没有读取系统通话记录的公开 API，只能在通话进行时实时观察。
final class CallTracker {
    static let shared = CallTracker()

    private let observer = CXCallObserver()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// 最近一次从本 App 发起拨号的（号码、时间）
    private var lastDialed: (number: String, date: Date)?
    /// 已在 observer 中出现过的呼出通话：UUID → (首次看到的时间, 是否接通过)
    private var seenOutgoingCalls: [UUID: (firstSeen: Date, everConnected: Bool)] = [:]

    private init() {
        observer.setDelegate(self, queue: DispatchQueue.main)
    }

    /// tel:// 打开成功（系统已接手拨号）后调用，用于跟踪后续结果
    func noteDialed(_ number: String) {
        lastDialed = (number, Date())
        beginBackgroundObservation()
    }

    /// 拨号后 App 会退到后台，申请一小段后台运行时间继续观察通话结果
    private func beginBackgroundObservation() {
        endBackgroundObservation()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CallOutcomeObservation") { [weak self] in
            self?.endBackgroundObservation()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 50) { [weak self] in
            self?.endBackgroundObservation()
        }
    }

    private func endBackgroundObservation() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private static func digitsOnly(_ number: String) -> String {
        number.filter { $0.isNumber }
    }
}

// MARK: - CXCallObserverDelegate

extension CallTracker: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard call.isOutgoing else { return }
        guard let dialed = lastDialed, Date().timeIntervalSince(dialed.date) < 90 else { return }

        var info = seenOutgoingCalls[call.uuid] ?? (firstSeen: Date(), everConnected: false)

        if call.hasConnected {
            // 通话已接通 → 标记该记录为已接通
            info.everConnected = true
            seenOutgoingCalls[call.uuid] = info
            logger.info("呼出已接通: \(dialed.number)")
            RecentDialStore.markStatus(number: dialed.number, connected: true, within: 300)
            return
        }

        if call.hasEnded {
            seenOutgoingCalls[call.uuid] = nil
            lastDialed = nil
            endBackgroundObservation()

            if info.everConnected {
                // 接通后正常结束，记录保留
                logger.info("呼出通话正常结束: \(dialed.number)")
            } else if Date().timeIntervalSince(info.firstSeen) < 10 {
                // 拨出后数秒内即挂断、从未接通 —— 视为“实际没有打出”，撤销记录并回退频次
                logger.info("呼出秒取消（未拨出），撤销记录: \(dialed.number)")
                RecentDialStore.undoRecentAdd(number: dialed.number, within: 120)
                RecentDialStore.decrementFrequency(digits: Self.digitsOnly(dialed.number))
            } else {
                // 响铃后未接听即结束 —— 保留记录并标记未接通
                logger.info("呼出响铃后未接通: \(dialed.number)")
                RecentDialStore.markStatus(number: dialed.number, connected: false, within: 300)
            }
        } else {
            seenOutgoingCalls[call.uuid] = info
        }
    }
}
