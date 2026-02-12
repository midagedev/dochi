import XCTest
@testable import Dochi

final class JamoMatcherTests: XCTestCase {

    // MARK: - Jamo Decomposition

    func testDecomposeHangulSyllable() {
        // 도 = ㄷ + ㅗ (no tail)
        let jamo = JamoMatcher.decompose("도")
        XCTAssertEqual(jamo, ["ㄷ", "ㅗ"])
    }

    func testDecomposeHangulWithTail() {
        // 한 = ㅎ + ㅏ + ㄴ
        let jamo = JamoMatcher.decompose("한")
        XCTAssertEqual(jamo, ["ㅎ", "ㅏ", "ㄴ"])
    }

    func testDecomposeMultipleSyllables() {
        // 도치야 = ㄷㅗ + ㅊㅣ + ㅇㅑ
        let jamo = JamoMatcher.decompose("도치야")
        XCTAssertEqual(jamo, ["ㄷ", "ㅗ", "ㅊ", "ㅣ", "ㅇ", "ㅑ"])
    }

    func testDecomposeNonHangul() {
        let jamo = JamoMatcher.decompose("abc")
        XCTAssertEqual(jamo, ["a", "b", "c"])
    }

    func testDecomposeMixedContent() {
        // 도A치 → ㄷㅗ A ㅊㅣ
        let jamo = JamoMatcher.decompose("도A치")
        XCTAssertEqual(jamo, ["ㄷ", "ㅗ", "A", "ㅊ", "ㅣ"])
    }

    func testDecomposeEmpty() {
        let jamo = JamoMatcher.decompose("")
        XCTAssertTrue(jamo.isEmpty)
    }

    // MARK: - Auto Threshold

    func testAutoThresholdMinimum() {
        // For small jamo counts, threshold should be at least 2
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 1), 2)
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 4), 2)
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 7), 2)
    }

    func testAutoThresholdScaling() {
        // max(2, 8/4) = 2
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 8), 2)
        // max(2, 12/4) = 3
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 12), 3)
        // max(2, 20/4) = 5
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 20), 5)
    }

    func testAutoThresholdZero() {
        XCTAssertEqual(JamoMatcher.autoThreshold(jamoCount: 0), 2)
    }

    // MARK: - Levenshtein Distance

    func testLevenshteinIdentical() {
        let a: [Character] = ["a", "b", "c"]
        XCTAssertEqual(JamoMatcher.levenshteinDistance(a, a), 0)
    }

    func testLevenshteinSingleEdit() {
        let a: [Character] = ["a", "b", "c"]
        let b: [Character] = ["a", "x", "c"]
        XCTAssertEqual(JamoMatcher.levenshteinDistance(a, b), 1)
    }

    func testLevenshteinEmpty() {
        let empty: [Character] = []
        let abc: [Character] = ["a", "b", "c"]
        XCTAssertEqual(JamoMatcher.levenshteinDistance(empty, abc), 3)
        XCTAssertEqual(JamoMatcher.levenshteinDistance(abc, empty), 3)
        XCTAssertEqual(JamoMatcher.levenshteinDistance(empty, empty), 0)
    }

    func testLevenshteinCompletelyDifferent() {
        let a: [Character] = ["a", "b", "c"]
        let b: [Character] = ["x", "y", "z"]
        XCTAssertEqual(JamoMatcher.levenshteinDistance(a, b), 3)
    }

    // MARK: - Exact Match

    func testExactMatchAtBeginning() {
        let result = JamoMatcher.isMatch(transcript: "도치야 안녕", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    func testExactMatchAtEnd() {
        let result = JamoMatcher.isMatch(transcript: "안녕 도치야", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    func testExactMatchInMiddle() {
        let result = JamoMatcher.isMatch(transcript: "안녕 도치야 뭐해", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    func testExactMatchAlone() {
        let result = JamoMatcher.isMatch(transcript: "도치야", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    // MARK: - Fuzzy Match

    func testFuzzyMatchSimilarPronunciation() {
        // 도찌야 is close to 도치야 (ㅉ vs ㅊ — one jamo difference)
        let result = JamoMatcher.isMatch(transcript: "도찌야 안녕", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchSlightVariation() {
        // 도키야 vs 도치야 (ㅋ vs ㅊ — one jamo difference)
        let result = JamoMatcher.isMatch(transcript: "도키야 안녕하세요", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    // MARK: - Non-Match

    func testNonMatchCompletelyDifferent() {
        let result = JamoMatcher.isMatch(transcript: "오늘 날씨가 좋다", wakeWord: "도치야")
        XCTAssertFalse(result)
    }

    func testNonMatchPartialOverlap() {
        // 바보야 shares ㅇㅑ with 도치야, but overall very different
        let result = JamoMatcher.isMatch(transcript: "바보야", wakeWord: "도치야")
        XCTAssertFalse(result)
    }

    // MARK: - Custom Threshold

    func testCustomThresholdStrict() {
        // With threshold 0, only exact match should pass
        let exact = JamoMatcher.isMatch(transcript: "도치야", wakeWord: "도치야", threshold: 0)
        XCTAssertTrue(exact)

        let fuzzy = JamoMatcher.isMatch(transcript: "도찌야", wakeWord: "도치야", threshold: 0)
        XCTAssertFalse(fuzzy)
    }

    func testCustomThresholdLenient() {
        // With a very high threshold, even dissimilar text could match
        let result = JamoMatcher.isMatch(transcript: "모피야", wakeWord: "도치야", threshold: 5)
        XCTAssertTrue(result)
    }

    // MARK: - Empty Strings

    func testEmptyTranscript() {
        let result = JamoMatcher.isMatch(transcript: "", wakeWord: "도치야")
        XCTAssertFalse(result)
    }

    func testEmptyWakeWord() {
        let result = JamoMatcher.isMatch(transcript: "도치야 안녕", wakeWord: "")
        XCTAssertFalse(result)
    }

    func testBothEmpty() {
        let result = JamoMatcher.isMatch(transcript: "", wakeWord: "")
        XCTAssertFalse(result)
    }

    // MARK: - Mixed Korean/English

    func testMixedKoreanEnglishTranscript() {
        let result = JamoMatcher.isMatch(transcript: "hey 도치야 what's up", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    func testEnglishOnlyWakeWord() {
        let result = JamoMatcher.isMatch(transcript: "hello dochi how are you", wakeWord: "dochi")
        XCTAssertTrue(result)
    }

    func testEnglishOnlyNonMatch() {
        let result = JamoMatcher.isMatch(transcript: "hello world", wakeWord: "dochi")
        XCTAssertFalse(result)
    }

    // MARK: - Space Handling

    func testSpacesInWakeWordAreRemoved() {
        // "도 치 야" with spaces should still match "도치야"
        let result = JamoMatcher.isMatch(transcript: "도치야 안녕", wakeWord: "도 치 야")
        XCTAssertTrue(result)
    }

    func testSpacesInTranscriptAreRemoved() {
        // Transcript with extra spaces between syllables
        let result = JamoMatcher.isMatch(transcript: "도 치 야 안녕", wakeWord: "도치야")
        XCTAssertTrue(result)
    }

    // MARK: - Longer Wake Words

    func testLongerWakeWord() {
        // Test a longer wake word (4 syllables)
        let result = JamoMatcher.isMatch(transcript: "안녕하세요 도치선생 오늘도 반가워", wakeWord: "도치선생")
        XCTAssertTrue(result)
    }

    func testLongerWakeWordFuzzy() {
        // 도치선생 vs 도치선셍 (one jamo difference in last syllable)
        let result = JamoMatcher.isMatch(transcript: "도치선셍 오늘", wakeWord: "도치선생")
        XCTAssertTrue(result)
    }

    // MARK: - Single Character Wake Word

    func testSingleCharacterWakeWord() {
        let result = JamoMatcher.isMatch(transcript: "야 뭐해", wakeWord: "야")
        XCTAssertTrue(result)
    }
}
