import Foundation
import LLMLocal

struct CalculatorTool: LocalTool {
    let displayName = "電卓"
    let iconName = "function"

    let definition = ToolDefinition(
        name: "calculator",
        description: "Evaluate a mathematical expression. Supports +, -, *, / and parentheses.",
        inputSchema: .object(
            properties: [
                "expression": .string(description: "The mathematical expression to evaluate, e.g. '(2+3)*4'"),
            ],
            required: ["expression"]
        )
    )

    func execute(arguments: String) async throws -> String {
        let expression = try parseArgument(arguments, key: "expression")
        let result = try evaluate(expression)
        // Format: remove trailing .0 for integer results
        if result == result.rounded() && !result.isInfinite && !result.isNaN {
            return String(Int(result))
        }
        return String(result)
    }

    // MARK: - Recursive Descent Parser

    private func evaluate(_ expr: String) throws -> Double {
        var chars = Array(expr.filter { !$0.isWhitespace })
        var pos = 0
        let result = try parseExpression(&chars, &pos)
        guard pos == chars.count else {
            throw ToolError.invalidInput("Unexpected character: \(chars[pos])")
        }
        return result
    }

    private func parseExpression(_ chars: inout [Character], _ pos: inout Int) throws -> Double {
        var result = try parseTerm(&chars, &pos)
        while pos < chars.count && (chars[pos] == "+" || chars[pos] == "-") {
            let op = chars[pos]
            pos += 1
            let right = try parseTerm(&chars, &pos)
            result = op == "+" ? result + right : result - right
        }
        return result
    }

    private func parseTerm(_ chars: inout [Character], _ pos: inout Int) throws -> Double {
        var result = try parseFactor(&chars, &pos)
        while pos < chars.count && (chars[pos] == "*" || chars[pos] == "/") {
            let op = chars[pos]
            pos += 1
            let right = try parseFactor(&chars, &pos)
            if op == "/" && right == 0 {
                throw ToolError.invalidInput("Division by zero")
            }
            result = op == "*" ? result * right : result / right
        }
        return result
    }

    private func parseFactor(_ chars: inout [Character], _ pos: inout Int) throws -> Double {
        guard pos < chars.count else {
            throw ToolError.invalidInput("Unexpected end of expression")
        }

        // Unary minus
        if chars[pos] == "-" {
            pos += 1
            return -(try parseFactor(&chars, &pos))
        }

        // Parentheses
        if chars[pos] == "(" {
            pos += 1
            let result = try parseExpression(&chars, &pos)
            guard pos < chars.count && chars[pos] == ")" else {
                throw ToolError.invalidInput("Missing closing parenthesis")
            }
            pos += 1
            return result
        }

        // Number
        var numStr = ""
        while pos < chars.count && (chars[pos].isNumber || chars[pos] == ".") {
            numStr.append(chars[pos])
            pos += 1
        }
        guard let number = Double(numStr) else {
            throw ToolError.invalidInput("Invalid number: \(numStr)")
        }
        return number
    }
}
