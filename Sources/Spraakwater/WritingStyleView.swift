import SwiftUI

/// Writing rules for every app, and a tone per kind of app.
struct WritingStyleView: View {
    @Bindable var settings: Settings
    @State private var category: AppCategory = .mail

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        PageContainer {
            PageHeader(
                title: "Schrijfstijl",
                subtitle: "Zo klinken je teksten nadat Claude ze heeft opgeruimd."
            )

            if !settings.cleanupEnabled {
                HStack(spacing: 10) {
                    Text("Opruimen met Claude staat uit, dus deze instellingen worden nu niet gebruikt.")
                        .font(.system(size: 13))
                    Button("Aanzetten") { settings.cleanupEnabled = true }
                        .buttonStyle(.link)
                }
                .foregroundStyle(Theme.red)
            }

            rules
            tone
        }
    }

    // MARK: Rules

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Schrijfregels", caption: "Gelden in elke app.")

            InlineAddField(prompt: "Bijvoorbeeld: houd het kort en direct", buttonTitle: "Toevoegen") {
                settings.addRule($0)
            }

            if settings.writingRules.isEmpty {
                Text("Nog geen regels.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(settings.writingRules, id: \.self) { rule in
                        RuleRow(rule: rule) { settings.removeRule(rule) }
                    }
                }
            }

            let open = WritingRules.suggestions.filter { suggestion in
                !settings.writingRules.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            }
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voorbeelden")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(open, id: \.self) { suggestion in
                            Button {
                                _ = settings.addRule(suggestion)
                            } label: {
                                Text("+ \(suggestion)")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Tone

    private var tone: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Toon per app", caption: "Spraakwater kijkt welke app vooraan staat en past de toon daarop aan.")

            Toggle("Toon aanpassen aan de app waarin je dicteert", isOn: $settings.contextEnabled)

            if settings.contextEnabled {
                UnderlineTabs(
                    tabs: AppCategory.styled.map { (tab: $0, title: $0.label) },
                    selection: $category
                )

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ToneStyle.allCases) { style in
                        ToneCard(style: style, selected: mode == style) {
                            settings.toneModes[category] = style
                        }
                    }
                }

                if mode == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Bijvoorbeeld: kort en vriendelijk, zonder aanhef", text: customText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(3...6)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
                        if customText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Vul een instructie in, anders wordt de toon niet aangepast.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.red)
                        }
                    }
                }

                HStack {
                    Text("Andere apps krijgen geen toonaanpassing. Alleen de naam van de app gaat mee naar Claude.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Standaardtonen herstellen") { settings.resetTones() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private var mode: ToneStyle {
        settings.toneModes[category] ?? .standard
    }

    private var customText: Binding<String> {
        Binding(
            get: { settings.toneCustom[category] ?? "" },
            set: { settings.toneCustom[category] = $0 }
        )
    }
}

private struct RuleRow: View {
    let rule: String
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(rule)
                .font(.system(size: 13.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            RowIconButton(symbol: "trash", label: "Verwijder regel", action: onDelete)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private struct ToneCard: View {
    let style: ToneStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Theme.red : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(style.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.red.opacity(0.07) : .primary.opacity(0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.red.opacity(0.75) : .primary.opacity(0.12), lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
