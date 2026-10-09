import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var isError: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle" : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isError ? Color.orange.opacity(0.55) : Color.white.opacity(0.2))

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isError ? Color.orange.opacity(0.8) : Color.white.opacity(0.6))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .lineSpacing(3)
        }
        .padding(28)
    }
}
