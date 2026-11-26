import SwiftUI

/// Scrolling page with the same width and margins as the overview.
struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 48)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionTitle: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            if let caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoekopdracht wissen")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
    }
}

/// Tabs with a line under the active one.
struct UnderlineTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.tab) { item in
                let selected = item.tab == selection
                Button {
                    selection = item.tab
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selected ? Theme.red : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A text field with an add button. The validation runs here, before anything is saved.
struct InlineAddField: View {
    let prompt: String
    let buttonTitle: String
    /// Returns what is wrong with the input, nil when it was accepted.
    let onAdd: (String) -> String?

    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
                    .onSubmit(add)
                    .onChange(of: text) { problem = nil }
                Button(action: add) {
                    Text(buttonTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.red))
                }
                .buttonStyle(.plain)
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
            }
        }
    }

    private func add() {
        if let error = onAdd(text) {
            problem = error
        } else {
            text = ""
            problem = nil
        }
    }
}

/// Lays out chips left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 600, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}
