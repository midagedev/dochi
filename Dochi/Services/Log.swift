import os

enum Log {
    static let app     = Logger(subsystem: "com.dochi.app", category: "App")
    static let llm     = Logger(subsystem: "com.dochi.app", category: "LLM")
    static let stt     = Logger(subsystem: "com.dochi.app", category: "STT")
    static let tts     = Logger(subsystem: "com.dochi.app", category: "TTS")
    static let mcp     = Logger(subsystem: "com.dochi.app", category: "MCP")
    static let tool    = Logger(subsystem: "com.dochi.app", category: "Tool")
    static let storage = Logger(subsystem: "com.dochi.app", category: "Storage")
}
