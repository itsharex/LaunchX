import SwiftUI

struct ContentView: View {
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(text: $searchText)
                .padding(20)

            if !searchText.isEmpty {
                Divider()
                ResultsListView(searchText: searchText)
            } else {
                Divider()
                EmptyStateView()
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .cornerRadius(16)
        // Ensure the view has a defined frame so the window doesn't collapse
        .frame(width: 650)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Subviews

struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(.secondary)

            TextField("LaunchX Search...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())  // Removes default border
                .font(.system(size: 26, weight: .light))
                .disableAutocorrection(true)
        }
    }
}

struct ResultsListView: View {
    let searchText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5) { item in
                    ResultRowView(index: item, searchText: searchText)
                }
            }
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 350)  // Limit height
    }
}

struct ResultRowView: View {
    let index: Int
    let searchText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18))
                .foregroundColor(.blue)

            VStack(alignment: .leading) {
                Text("Result \(index + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Matching '\(searchText)'")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Text("Cmd + \(index + 1)")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        HStack {
            Text("Type to search apps, files, or bookmarks...")
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()

            Text("⏎ to open")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(20)
    }
}

// MARK: - Helpers

// Helper for Acrylic/Blur background
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
