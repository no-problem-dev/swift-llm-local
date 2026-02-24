import Foundation
import LLMLocal

struct DiceRollTool: LocalTool {
    let displayName = "サイコロ"
    let iconName = "dice"

    let definition = ToolDefinition(
        name: "dice_roll",
        description: "Roll dice using standard notation. For example '2d6' rolls two six-sided dice.",
        inputSchema: .object(
            properties: [
                "notation": .string(description: "Dice notation in NdS format, e.g. '1d6', '2d20', '3d8'"),
            ],
            required: ["notation"]
        )
    )

    func execute(arguments: String) async throws -> String {
        let notation = try parseArgument(arguments, key: "notation")

        let parts = notation.lowercased().split(separator: "d")
        guard parts.count == 2,
              let count = Int(parts[0]),
              let sides = Int(parts[1]),
              count > 0, count <= 100,
              sides > 0, sides <= 1000 else {
            throw ToolError.invalidInput("Invalid dice notation: \(notation). Use NdS format like '2d6'.")
        }

        let rolls = (0..<count).map { _ in Int.random(in: 1...sides) }
        let total = rolls.reduce(0, +)

        if count == 1 {
            return "Result: \(total)"
        }
        return "Rolls: \(rolls) Total: \(total)"
    }
}
