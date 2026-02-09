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

    // MARK: - Agent

    enum Agent {
        static let defaultName = "도치"
        static let defaultWakeWord = "도치야"
        static let defaultDescription = "기본 음성 비서 에이전트"

        static let defaultBaseSystemPrompt = """
        당신은 가정용 음성 비서입니다.
        다음 규칙을 따르세요:
        - 한국어로 대답하세요.
        - 간결하고 자연스러운 구어체로 말하세요.
        - 음성 출력에 적합하도록 짧은 문장으로 답변하세요.
        - 마크다운 서식을 사용하지 마세요.
        """

        static let defaultPersona = """
        이름: 도치
        성격: 밝고 친근한 비서. 존댓말을 기본으로 하되, 사용자가 반말을 원하면 맞춰줍니다.
        말투: 자연스럽고 따뜻한 톤. 불필요하게 길게 말하지 않습니다.
        """
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
