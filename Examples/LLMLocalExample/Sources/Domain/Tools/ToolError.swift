import Foundation

enum ToolError: LocalizedError {
    case invalidInput(String)
    case missingArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .missingArgument(let key): "Missing required argument: \(key)"
        }
    }
}

// MARK: - JSON Argument Helpers

func parseArgument(_ json: String, key: String) throws -> String {
    let args = parseJSON(json)
    guard let value = args[key] as? String, !value.isEmpty else {
        throw ToolError.missingArgument(key)
    }
    return value
}

func parseJSON(_ json: String) -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return dict
}
