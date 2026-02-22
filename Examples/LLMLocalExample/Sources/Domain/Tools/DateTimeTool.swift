import Foundation
import LLMLocal

struct DateTimeTool: LocalTool {
    let displayName = "日時"
    let iconName = "calendar.badge.clock"

    let definition = ToolDefinition(
        name: "date_time",
        description: "Get the current date and time. Useful when the user asks about today's date or current time.",
        parameters: [
            .optional("format", type: .string, description: "Output format: 'iso8601', 'readable', 'date_only', 'time_only'. Defaults to 'readable'."),
            .optional("timezone", type: .string, description: "Timezone identifier, e.g. 'Asia/Tokyo', 'UTC'. Defaults to the device timezone.")
        ]
    )

    func execute(arguments: String) async throws -> String {
        let args = parseJSON(arguments)
        let format = args["format"] as? String ?? "readable"
        let timezoneName = args["timezone"] as? String

        let formatter = DateFormatter()
        if let tz = timezoneName {
            guard let timezone = TimeZone(identifier: tz) else {
                throw ToolError.invalidInput("Unknown timezone: \(tz)")
            }
            formatter.timeZone = timezone
        }

        let now = Date()

        switch format {
        case "iso8601":
            let iso = ISO8601DateFormatter()
            if let tz = timezoneName, let timezone = TimeZone(identifier: tz) {
                iso.timeZone = timezone
            }
            return iso.string(from: now)
        case "date_only":
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter.string(from: now)
        case "time_only":
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter.string(from: now)
        default: // "readable"
            formatter.dateStyle = .long
            formatter.timeStyle = .medium
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter.string(from: now)
        }
    }
}
