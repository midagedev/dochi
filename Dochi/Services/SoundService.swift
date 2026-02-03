import AppKit

final class SoundService: SoundServiceProtocol {
    init() {}

    /// 입력 완료 효과음
    func playInputComplete() {
        NSSound(named: "Pop")?.play()
    }

    /// 웨이크워드 감지 효과음
    func playWakeWordDetected() {
        NSSound(named: "Ping")?.play()
    }
}
