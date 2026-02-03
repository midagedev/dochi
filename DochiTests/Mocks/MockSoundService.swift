import Foundation
@testable import Dochi

final class MockSoundService: SoundServiceProtocol {
    var inputCompletePlayCount = 0
    var wakeWordDetectedPlayCount = 0

    func playInputComplete() {
        inputCompletePlayCount += 1
    }

    func playWakeWordDetected() {
        wakeWordDetectedPlayCount += 1
    }
}
