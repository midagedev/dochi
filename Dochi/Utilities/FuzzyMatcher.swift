import Foundation

/// 한글 자모 기반 퍼지 매칭 유틸리티
/// JamoMatcher.decompose()를 재사용하여 초성 검색, 자모 부분 매칭, 영문 매칭을 지원한다.
enum FuzzyMatcher {

    /// 검색 결과와 점수
    struct ScoredItem<T> {
        let item: T
        let score: Int
    }

    // MARK: - Public API

    /// 주어진 쿼리로 아이템을 필터링하고 점수순으로 정렬한다.
    /// - Parameters:
    ///   - items: 검색 대상 아이템
    ///   - query: 검색어 (빈 문자열이면 전체 반환)
    ///   - keyPath: 아이템에서 검색 대상 문자열을 추출하는 키패스
    ///   - recentIds: 최근 사용한 아이템 ID 목록 (가산점 부여용)
    ///   - idKeyPath: 아이템에서 ID를 추출하는 키패스
    /// - Returns: 점수 내림차순 정렬된 아이템 배열
    static func filter<T>(
        items: [T],
        query: String,
        keyPath: KeyPath<T, String>,
        recentIds: [String] = [],
        idKeyPath: KeyPath<T, String>? = nil
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            // 쿼리 없으면 최근 사용 순 + 원래 순서
            if let idKP = idKeyPath, !recentIds.isEmpty {
                return items.sorted { a, b in
                    let aIdx = recentIds.firstIndex(of: a[keyPath: idKP]) ?? Int.max
                    let bIdx = recentIds.firstIndex(of: b[keyPath: idKP]) ?? Int.max
                    return aIdx < bIdx
                }
            }
            return items
        }

        let scored: [ScoredItem<T>] = items.compactMap { item in
            let title = item[keyPath: keyPath]
            let score = matchScore(title: title, query: trimmed)
            guard score > 0 else { return nil }

            var bonus = score
            // 최근 사용 보너스
            if let idKP = idKeyPath, recentIds.contains(item[keyPath: idKP]) {
                bonus += 100
            }
            return ScoredItem(item: item, score: bonus)
        }

        return scored.sorted { $0.score > $1.score }.map(\.item)
    }

    // MARK: - 매칭 점수 계산

    /// 타이틀과 쿼리의 매칭 점수를 계산한다.
    /// - Returns: 0이면 매칭 실패, 양수이면 매칭 성공 (높을수록 좋음)
    static func matchScore(title: String, query: String) -> Int {
        guard !query.isEmpty else { return 0 }

        let titleLower = title.lowercased()
        let queryLower = query.lowercased()

        // 1. 영문 exact prefix match
        if titleLower.hasPrefix(queryLower) {
            return 50
        }

        // 2. 영문 contains match
        if titleLower.localizedCaseInsensitiveContains(queryLower) {
            return 30
        }

        // 3. 초성 매칭 (쿼리가 전부 초성인 경우)
        if isAllChoseong(query) {
            let titleChoseong = extractChoseong(title)
            if titleChoseong.hasPrefix(query) {
                return 50  // 초성 prefix
            }
            if titleChoseong.contains(query) {
                return 30  // 초성 부분 매칭
            }
        }

        // 4. 자모 분해 부분 매칭
        let titleJamo = JamoMatcher.decompose(titleLower)
        let queryJamo = JamoMatcher.decompose(queryLower)

        if !queryJamo.isEmpty && containsSubsequence(titleJamo, queryJamo) {
            return 10
        }

        return 0
    }

    // MARK: - 초성 관련

    /// 초성 테이블 (19개)
    private static let choseongTable: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
        "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 모든 문자가 초성(ㄱ~ㅎ)인지 확인
    static func isAllChoseong(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let choseongSet: Set<Character> = Set(choseongTable)
        return text.allSatisfy { choseongSet.contains($0) }
    }

    /// 문자열에서 한글 음절의 초성만 추출 (공백 제거)
    static func extractChoseong(_ text: String) -> String {
        let hangulBase: UInt32 = 0xAC00
        let hangulEnd: UInt32 = 0xD7A3
        let vowelCount: UInt32 = 21
        let tailCount: UInt32 = 28

        var result = ""
        for char in text {
            // 공백 무시 (초성 검색 시 공백이 방해되지 않도록)
            if char == " " { continue }

            guard let scalar = char.unicodeScalars.first,
                  char.unicodeScalars.count == 1,
                  scalar.value >= hangulBase,
                  scalar.value <= hangulEnd else {
                // 한글 음절이 아니면 원본 유지
                result.append(char)
                continue
            }

            let code = scalar.value - hangulBase
            let leadIndex = Int(code / (vowelCount * tailCount))
            result.append(choseongTable[leadIndex])
        }
        return result
    }

    // MARK: - 자모 부분 매칭

    /// titleJamo가 queryJamo를 연속 부분 배열로 포함하는지 확인
    private static func containsSubsequence(_ haystack: [Character], _ needle: [Character]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        let limit = haystack.count - needle.count
        for start in 0...limit {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}
