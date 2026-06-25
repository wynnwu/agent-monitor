public func defaultClaudeCandidates(home: String) -> [String] {
    ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
}

public func resolveClaudeBinary(candidates: [String], exists: (String) -> Bool) -> String? {
    candidates.first(where: exists)
}
