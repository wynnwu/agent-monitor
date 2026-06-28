import Foundation

public struct TranscriptRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let role: Role
    public let text: String
    public let toolUses: [String]
    public let isToolResult: Bool
    public let isMeta: Bool
    public let timestamp: Date?
    public let model: String?       // assistant turns carry the model id
    public let stopReason: String?  // assistant turns: "end_turn", "tool_use", … (nil if absent)
    public enum Role: String, Sendable { case user, assistant, system, other }

    public init(id: String, role: Role, text: String, toolUses: [String],
                isToolResult: Bool, isMeta: Bool, timestamp: Date?, model: String? = nil,
                stopReason: String? = nil) {
        self.id = id; self.role = role; self.text = text; self.toolUses = toolUses
        self.isToolResult = isToolResult; self.isMeta = isMeta; self.timestamp = timestamp
        self.model = model; self.stopReason = stopReason
    }
}
