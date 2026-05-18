import AVFoundation
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "DTMFPlayer")

class DTMFPlayer {
    static let shared = DTMFPlayer()
    
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var deactivateTimer: Timer?
    private var deactivateAttemptCount = 0
    private let maxDeactivateAttempts = 5
    
    private let dtmfFileNames: [String: String] = [
        "0": "dtmf-0",
        "1": "dtmf-1",
        "2": "dtmf-2",
        "3": "dtmf-3",
        "4": "dtmf-4",
        "5": "dtmf-5",
        "6": "dtmf-6",
        "7": "dtmf-7",
        "8": "dtmf-8",
        "9": "dtmf-9",
        "*": "dtmf-star",
        "#": "dtmf-hash",
    ]
    
    private init() {
        preloadSounds()
    }

    private func activateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            logger.debug("音频会话激活失败: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.debug("音频会话停用失败: \(error.localizedDescription)")
        }
    }
    
    private func preloadSounds() {
        for (digit, fileName) in dtmfFileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") ??
                  Bundle.main.url(forResource: fileName, withExtension: "mp3") ??
                  Bundle.main.url(forResource: fileName, withExtension: "caf") else {
                continue
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                audioPlayers[digit] = player
            } catch {
                logger.debug("音频加载失败: \(digit)")
            }
        }
    }
    
    func playDTMF(digit: String) {
        guard AppSettings.shared.keypadSoundEnabled else { return }

        activateAudioSession()

        if let player = audioPlayers[digit] {
            player.stop()
            player.currentTime = 0
            player.play()
        } else {
            playSystemSound(for: digit)
        }

        scheduleDeactivate()
    }
    
    private func scheduleDeactivate() {
        deactivateTimer?.invalidate()
        deactivateAttemptCount = 0
        deactivateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.deactivateAttemptCount += 1
            
            let anyPlaying = self.audioPlayers.values.contains { $0.isPlaying }
            if !anyPlaying || self.deactivateAttemptCount >= self.maxDeactivateAttempts {
                self.deactivateAudioSession()
                timer.invalidate()
                self.deactivateTimer = nil
            }
        }
    }
    
    func stopDTMF() {
        for player in audioPlayers.values {
            player.stop()
        }
        deactivateTimer?.invalidate()
        deactivateTimer = nil
        deactivateAudioSession()
    }
    
    private func playSystemSound(for digit: String) {
        let soundID: SystemSoundID
        switch digit {
        case "0": soundID = 1200
        case "1": soundID = 1201
        case "2": soundID = 1202
        case "3": soundID = 1203
        case "4": soundID = 1204
        case "5": soundID = 1205
        case "6": soundID = 1206
        case "7": soundID = 1207
        case "8": soundID = 1208
        case "9": soundID = 1209
        case "*": soundID = 1210
        case "#": soundID = 1211
        default: return
        }
        
        AudioServicesPlaySystemSound(soundID)
    }
}
