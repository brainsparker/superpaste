import SwiftUI

/// Resources page with links to documentation and support
struct ResourcesPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Resources")
                    .font(.title2.bold())

                // Resource links
                VStack(spacing: 12) {
                    ResourceLink(
                        icon: "book.fill",
                        title: "Documentation",
                        description: "Learn tips and tricks for SuperPaste",
                        url: "https://superpaste.app/docs"
                    )

                    ResourceLink(
                        icon: "bubble.left.fill",
                        title: "Send Feedback",
                        description: "We'd love to hear from you",
                        url: "mailto:feedback@superpaste.app"
                    )

                    ResourceLink(
                        icon: "ant.fill",
                        title: "Report a Bug",
                        description: "Help us squash issues",
                        url: "https://github.com/superpaste/superpaste/issues"
                    )

                    ResourceLink(
                        icon: "globe",
                        title: "You.com",
                        description: "Powered by You.com AI",
                        url: "https://you.com"
                    )
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A clickable resource link card
struct ResourceLink: View {
    let icon: String
    let title: String
    let description: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
