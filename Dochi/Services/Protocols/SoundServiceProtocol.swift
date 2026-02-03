import Foundation

/// UI 사운드 효과 서비스 프로토콜
protocol SoundServiceProtocol {
    /// 입력 완료 효과음
    func playInputComplete()

    /// 웨이크워드 감지 효과음
    func playWakeWordDetected()
}
