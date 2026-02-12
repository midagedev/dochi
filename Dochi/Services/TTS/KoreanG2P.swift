import Foundation

/// Korean Grapheme-to-Phoneme converter for Supertonic TTS model input.
/// Converts Korean text (Hangul) into a phoneme sequence for ONNX model inference.
enum KoreanG2P {
    // Unicode Hangul block ranges
    private static let hangulBase: UInt32 = 0xAC00
    private static let hangulEnd: UInt32 = 0xD7A3
    private static let leadingCount = 19
    private static let vowelCount = 21
    private static let trailingCount = 28

    // Jamo decomposition tables
    private static let leadingJamo = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    private static let vowelJamo = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
        "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
    ]

    private static let trailingJamo = [
        "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ",
        "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    // Phoneme mapping for IPA-like representation
    private static let leadingPhonemes = [
        "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s",
        "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
    ]

    private static let vowelPhonemes = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa",
        "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"
    ]

    private static let trailingPhonemes = [
        "", "k", "kk", "ks", "n", "nj", "nh", "t", "l", "lk",
        "lm", "lp", "ls", "lt", "lp", "lh", "m", "p", "ps", "s",
        "ss", "ng", "j", "ch", "k", "t", "p", "h"
    ]

    /// Convert Korean text to a phoneme sequence.
    /// Returns a string of space-separated phoneme tokens.
    static func convert(_ text: String) -> [String] {
        var phonemes: [String] = []

        for char in text {
            guard let scalar = char.unicodeScalars.first else {
                // Non-character (spaces, punctuation)
                if char == " " {
                    phonemes.append("<sp>")
                } else if ".,!?;:".contains(char) {
                    phonemes.append("<pau>")
                }
                continue
            }

            let code = scalar.value

            // Check if it's a Hangul syllable
            if code >= hangulBase && code <= hangulEnd {
                let syllableIndex = Int(code - hangulBase)
                let leadingIndex = syllableIndex / (vowelCount * trailingCount)
                let vowelIndex = (syllableIndex % (vowelCount * trailingCount)) / trailingCount
                let trailingIndex = syllableIndex % trailingCount

                let lp = leadingPhonemes[leadingIndex]
                let vp = vowelPhonemes[vowelIndex]
                let tp = trailingPhonemes[trailingIndex]

                if !lp.isEmpty { phonemes.append(lp) }
                phonemes.append(vp)
                if !tp.isEmpty { phonemes.append(tp) }
            } else if char.isASCII && char.isLetter {
                // Pass through ASCII letters as-is
                phonemes.append(String(char).lowercased())
            } else if char.isNumber {
                // Numbers: spell out each digit
                phonemes.append(digitPhoneme(char))
            }
        }

        return phonemes
    }

    /// Convert a digit character to Korean phoneme representation.
    private static func digitPhoneme(_ char: Character) -> String {
        switch char {
        case "0": return "yeong"
        case "1": return "il"
        case "2": return "i"
        case "3": return "sam"
        case "4": return "sa"
        case "5": return "o"
        case "6": return "yuk"
        case "7": return "chil"
        case "8": return "pal"
        case "9": return "gu"
        default: return ""
        }
    }
}
