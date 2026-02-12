import Foundation
import AppKit
import os

@MainActor
protocol SoundServiceProtocol {
    func playWakeWordDetected()
    func playInputComplete()
}

@MainActor
final class SoundService: SoundServiceProtocol {
    func playWakeWordDetected() {
        NSSound(named: "Tink")?.play()
        Log.app.debug("Sound: wake word detected")
    }

    func playInputComplete() {
        NSSound(named: "Pop")?.play()
        Log.app.debug("Sound: input complete")
    }
}
