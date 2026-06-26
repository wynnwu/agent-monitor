import SwiftUI

/// A small capsule showing a git branch. Shared by the main list rows and the
/// detail-window header so the two stay visually consistent.
struct BranchPill: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            Text(name).font(.system(size: 13)).lineLimit(1)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}
