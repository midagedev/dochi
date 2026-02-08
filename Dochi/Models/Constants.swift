import Foundation

enum Constants {
    // MARK: - Timing

    enum Timing {
        /// TTS 재생 완료 후 에코 방지 딜레이 (밀리초)
        static let echoPreventionDelayMs: UInt64 = 400
        /// TTS 완료 대기 폴링 간격 (밀리초)
        static let ttsCompletionPollMs: UInt64 = 100
    }

    // MARK: - LLM

    enum LLM {
        static let anthropicAPIVersion = "2023-06-01"
        static let anthropicMaxTokens = 4096
        /// 경량 분석용 모델 (대화 요약, 컨텍스트 압축 등)
        static let simpleAnalysisModel = "claude-haiku-4-5-20251001"
        /// 경량 분석 요청 시 최대 토큰 수
        static let simpleAnalysisMaxTokens = 300
        /// OpenAI 경량 분석용 모델
        static let openaiSimpleModel = "gpt-4.1-nano"
        /// Z.AI 경량 분석용 모델
        static let zaiSimpleModel = "glm-4.7"
    }

    // MARK: - Session

    enum Session {
        /// 종료 질문에 대한 긍정 응답 키워드
        static let endKeywords = [
            "응", "어", "예", "네", "그래", "종료", "끝", "됐어", "괜찮아",
            "ㅇㅇ", "웅", "yes", "yeah", "ok", "okay"
        ]
        /// 사용자가 직접 세션 종료를 요청하는 트리거
        static let endTriggers = [
            "대화종료", "대화끝", "세션종료", "세션끝",
            "그만할게", "그만하자", "이만할게", "이만하자",
            "끝내자", "끝낼게", "종료해", "종료할게",
            "잘가", "잘있어", "바이바이", "bye", "goodbye"
        ]
        static let askEndMessage = "대화를 종료할까요?"
        static let endConfirmMessage = "네, 대화를 종료할게요. 다음에 또 불러주세요!"
        static let unknownUserLabel = "미확인"
    }

    // MARK: - Defaults

    enum Defaults {
        static let wakeWord = "도치야"
        static let supertonicVoice = "F1"
        static let ttsSpeed: Float = 1.15
        static let ttsDiffusionSteps = 10
        static let chatFontSize: Double = 14.0
        static let sttSilenceTimeout: Double = 1.0
        static let contextMaxSize = 15360
    }
}
