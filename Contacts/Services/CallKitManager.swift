import Foundation
import CallKit
import UIKit
import AVFoundation

class CallKitManager: NSObject {
    static let shared = CallKitManager()
    
    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    
    private override init() {
        // 配置 CallKit Provider
        let config = CXProviderConfiguration(localizedName: "T9u")
        config.supportsVideo = false
        config.supportedHandleTypes = [.phoneNumber]
        
        // 使用应用图标作为 CallKit 图标
        if let iconImage = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = iconImage.pngData()
        }
        
        provider = CXProvider(configuration: config)
        super.init()
        
        provider.setDelegate(self, queue: DispatchQueue.main)
    }
    
    // MARK: - 报告拨出通话
    func reportOutgoingCall(to phoneNumber: String) {
        let handle = CXHandle(type: .phoneNumber, value: phoneNumber)
        let uuid = UUID()
        currentCallUUID = uuid
        
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = false
        
        let transaction = CXTransaction(action: startCallAction)
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("[CallKit] 报告拨出通话失败: \(error.localizedDescription)")
                self?.currentCallUUID = nil
            } else {
                print("[CallKit] 已报告拨出通话: \(phoneNumber)")
            }
        }
    }
    
    // MARK: - 报告通话结束
    func reportCallEnded() {
        guard let uuid = currentCallUUID else { return }
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKit] 报告通话结束失败: \(error.localizedDescription)")
            } else {
                print("[CallKit] 已报告通话结束")
            }
        }
        
        currentCallUUID = nil
    }
}

// MARK: - CXProviderDelegate 实现
extension CallKitManager: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
        print("[CallKit] Provider did reset")
        currentCallUUID = nil
    }
    
    // MARK: - 执行拨号动作
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // 对于第三方拨号应用，不应该通过CallKit发起拨号
        // 拨号已经在KeypadViewModel中直接通过tel:// URL完成
        // 这里只需要确认动作即可
        print("[CallKit] CXStartCallAction performed for: \(action.handle.value)")
        action.fulfill()
    }
    
    // MARK: - 执行挂断动作
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // 通话结束处理
        print("[CallKit] 通话已结束")
        action.fulfill()
    }
    
    // MARK: - 音频会话管理
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("[CallKit] 音频会话已激活")
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("[CallKit] 音频会话已失活")
    }
}
