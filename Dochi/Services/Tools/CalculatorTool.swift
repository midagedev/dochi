import Foundation

@MainActor
final class CalculatorTool: BuiltInToolProtocol {
    let name = "calculate"
    let category: ToolCategory = .safe
    let description = "수학 표현식을 계산합니다. 사칙연산, 거듭제곱, 괄호, 수학 함수를 지원합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "expression": ["type": "string", "description": "계산할 수식 (예: '(3.14 * 5^2) + sqrt(144)')"],
            ],
            "required": ["expression"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let expression = arguments["expression"] as? String, !expression.isEmpty else {
            return ToolResult(toolCallId: "", content: "expression 파라미터가 필요합니다.", isError: true)
        }

        // Sanitize: only allow safe math characters
        let sanitized = expression
            .replacingOccurrences(of: "^", with: "**")  // power notation
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")

        // Use NSExpression for basic math
        let nsExpr = sanitized
            .replacingOccurrences(of: "**", with: "**")  // NSExpression uses ** for power

        do {
            let result = try evaluateExpression(nsExpr)
            return ToolResult(toolCallId: "", content: "\(expression) = \(formatNumber(result))")
        } catch {
            return ToolResult(toolCallId: "", content: "계산 실패: \(error.localizedDescription)\n입력: \(expression)", isError: true)
        }
    }

    private func evaluateExpression(_ expr: String) throws -> Double {
        // Handle math functions manually
        var processed = expr
        processed = replaceMathFunc(in: processed, name: "sqrt") { sqrt($0) }
        processed = replaceMathFunc(in: processed, name: "abs") { abs($0) }
        processed = replaceMathFunc(in: processed, name: "sin") { sin($0) }
        processed = replaceMathFunc(in: processed, name: "cos") { cos($0) }
        processed = replaceMathFunc(in: processed, name: "tan") { tan($0) }
        processed = replaceMathFunc(in: processed, name: "log") { log10($0) }
        processed = replaceMathFunc(in: processed, name: "ln") { log($0) }
        processed = processed.replacingOccurrences(of: "pi", with: String(Double.pi))
        processed = processed.replacingOccurrences(of: "e", with: String(M.e))
        processed = processed.replacingOccurrences(of: "**", with: " ** ")

        // Validate: only digits, operators, whitespace, dots, parentheses
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
            .union(CharacterSet(charactersIn: "*"))
        let testStr = processed.replacingOccurrences(of: " ** ", with: " ")
        guard testStr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CalcError.invalidExpression
        }

        // Handle ** (power) by converting to pow() calls
        processed = handlePower(processed)

        let nsExpression = NSExpression(format: processed)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw CalcError.evaluationFailed
        }
        return result.doubleValue
    }

    private func replaceMathFunc(in expr: String, name: String, _ fn: (Double) -> Double) -> String {
        var result = expr
        while let range = result.range(of: "\(name)(") {
            // Find matching closing paren
            let startIdx = range.upperBound
            var depth = 1
            var idx = startIdx
            while idx < result.endIndex && depth > 0 {
                if result[idx] == "(" { depth += 1 }
                if result[idx] == ")" { depth -= 1 }
                if depth > 0 { idx = result.index(after: idx) }
            }
            if depth == 0 {
                let innerStr = String(result[startIdx..<idx])
                if let innerVal = Double(innerStr.trimmingCharacters(in: .whitespaces)) {
                    let computed = fn(innerVal)
                    result.replaceSubrange(range.lowerBound...idx, with: String(computed))
                } else {
                    break
                }
            } else {
                break
            }
        }
        return result
    }

    private func handlePower(_ expr: String) -> String {
        // Simple ** to pow() conversion for cases like "2 ** 3"
        var result = expr
        while let range = result.range(of: " ** ") {
            let before = String(result[result.startIndex..<range.lowerBound])
            let after = String(result[range.upperBound...])

            // Extract the number before **
            let beforeTokens = before.split(separator: " ")
            guard let base = beforeTokens.last, let baseVal = Double(base) else { break }
            let prefix = beforeTokens.dropLast().joined(separator: " ")

            // Extract the number after **
            let afterTokens = after.split(separator: " ", maxSplits: 1)
            guard let exp = afterTokens.first, let expVal = Double(exp) else { break }
            let suffix = afterTokens.dropFirst().joined(separator: " ")

            let powResult = pow(baseVal, expVal)
            result = [prefix, String(powResult), suffix]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return result
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let formatted = String(format: "%.10g", value)
        return formatted
    }

    private enum CalcError: LocalizedError {
        case invalidExpression
        case evaluationFailed

        var errorDescription: String? {
            switch self {
            case .invalidExpression: "유효하지 않은 수식입니다."
            case .evaluationFailed: "수식을 계산할 수 없습니다."
            }
        }
    }

    private enum M {
        static let e = 2.718281828459045
    }
}
