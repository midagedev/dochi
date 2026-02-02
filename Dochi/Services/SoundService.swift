import AppKit

enum SoundService {
    /// 입력 완료 효과음
    static func playInputComplete() {
        NSSound(named: "Pop")?.play()
    }

    /// 웨이크워드 감지 효과음
    static func playWakeWordDetected() {
        NSSound(named: "Ping")?.play()
    }
}
