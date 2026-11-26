import AppKit
import SwiftUI

enum DashboardSection: Hashable {
    case overview
    case dictionary
    case style
    case settings
}

@Observable
final class DashboardState {
    static let shared = DashboardState()
    var section: DashboardSection = .overview
}

/// The main window: overview with statistics and history, and the settings next to it.
enum MainWindow {
    private static var window: NSWindow?

    static func show(_ section: DashboardSection = .overview) {
        DashboardState.shared.section = section
        if window == nil {
            let hosting = NSHostingController(
                rootView: DashboardView(controller: AppController.shared, state: DashboardState.shared)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Spraakwater"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 940, height: 680))
            newWindow.contentMinSize = NSSize(width: 820, height: 560)
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Opens the settings section. Kept as one call because several places ask for the settings.
enum SettingsWindow {
    static func show() { MainWindow.show(.settings) }
}

struct DashboardView: View {
    let controller: AppController
    @Bindable var state: DashboardState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state)
                .frame(width: 210)
            Divider()
            Group {
                switch state.section {
                case .overview:
                    OverviewView(controller: controller)
                case .dictionary:
                    DictionaryView(settings: controller.settings)
                case .style:
                    WritingStyleView(settings: controller.settings)
                case .settings:
                    ScrollView {
                        SettingsView(settings: controller.settings, showsHeader: false)
                            .frame(maxWidth: 560)
                            .padding(.top, 36)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottomTrailing) {
                if state.section == .overview { ArtworkBackdrop() }
            }
        }
        .tint(Theme.red)
        .ignoresSafeArea()
    }
}

/// The artwork, faint in the bottom right corner. It sits above the content so the pinned day headers
/// do not cut it, but it is faint enough to leave the text readable and it ignores clicks.
private struct ArtworkBackdrop: View {
    var body: some View {
        if let image = Bundle.main.image(forResource: "extince") {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 470, height: 470)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .mask(
                    // Fades out from the corner in every direction, so the picture has no visible edge.
                    RadialGradient(
                        colors: [.black, .black.opacity(0.75), .clear],
                        center: .bottomTrailing,
                        startRadius: 60,
                        endRadius: 440
                    )
                )
                .opacity(0.2)
                .offset(x: 24, y: 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct Sidebar: View {
    @Bindable var state: DashboardState

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("Spraakwater")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)

            SidebarRow(title: "Overzicht", symbol: "house", selected: state.section == .overview) {
                state.section = .overview
            }
            SidebarRow(title: "Woordenlijst", symbol: "text.book.closed", selected: state.section == .dictionary) {
                state.section = .dictionary
            }
            SidebarRow(title: "Schrijfstijl", symbol: "pencil.line", selected: state.section == .style) {
                state.section = .style
            }
            SidebarRow(title: "Instellingen", symbol: "gearshape", selected: state.section == .settings) {
                state.section = .settings
            }

            Spacer()

            Text("Versie \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        // Room for the window buttons, which sit on top of the sidebar.
        .padding(.top, 46)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Theme.red : .secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(selected ? 0.08 : hovering ? 0.04 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Overview

private struct OverviewView: View {
    let controller: AppController
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                StatsRow(stats: controller.statistics)
                HistorySection(controller: controller, query: $query)
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Houd")
                ForEach(controller.settings.hotkey.keyCaps, id: \.self) { KeyCap(symbol: $0, large: true) }
                Text("ingedrukt om te dicteren")
            }
            .font(.system(size: 22, weight: .semibold))

            if let problem = controller.settings.configurationProblem {
                HStack(spacing: 8) {
                    Text("Nog niet klaar: \(problem)")
                        .foregroundStyle(Theme.red)
                    Button("Naar instellingen") { DashboardState.shared.section = .settings }
                        .buttonStyle(.link)
                }
                .font(.system(size: 13))
            } else if let message = controller.message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.red)
            }
        }
    }
}

private struct StatsRow: View {
    let stats: StatisticsStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell("Woorden gedicteerd") {
                Text(stats.words, format: .number.locale(.dutch))
            }
            divider
            cell("Tijd bespaard", help: "Ten opzichte van typen met \(Int(StatisticsStore.typingWordsPerMinute)) woorden per minuut.") {
                Text(StatisticsStore.formatted(duration: stats.timeSaved))
            }
            divider
            cell("Dagen op rij") {
                Text("\(stats.streak)")
                unit(stats.streak == 1 ? "dag" : "dagen")
            }
            divider
            cell("Gemiddeld tempo") {
                if let wpm = stats.wordsPerMinute {
                    Text("\(wpm)")
                    unit("woorden per min")
                } else {
                    Text("-")
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var divider: some View {
        Divider().frame(height: 44).padding(.horizontal, 20)
    }

    private func unit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func cell(_ label: String, help: String? = nil, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                value()
                    .font(.system(size: 24, weight: .medium).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }
}

// MARK: History

private struct DayGroup: Identifiable {
    let day: Date
    let entries: [HistoryEntry]
    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Vandaag" }
        if calendar.isDateInYesterday(day) { return "Gisteren" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        let text = sameYear
            ? day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.dutch))
            : day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.dutch))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

private struct HistorySection: View {
    let controller: AppController
    @Binding var query: String

    private var filtered: [HistoryEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return controller.history.entries }
        return controller.history.entries.filter {
            $0.text.localizedStandardContains(term) || ($0.appName?.localizedStandardContains(term) ?? false)
        }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, entries: byDay[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Geschiedenis")
                    .font(.system(size: 16, weight: .semibold))
                if !controller.history.entries.isEmpty {
                    Text("\(controller.history.entries.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SearchField(text: $query, prompt: "Zoek in je dictaten")
            }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if !controller.settings.historyEnabled && controller.history.entries.isEmpty {
            emptyMessage("De geschiedenis staat uit, nieuwe dictaten worden niet bewaard.") {
                Button("Aanzetten in instellingen") { DashboardState.shared.section = .settings }
                    .buttonStyle(.link)
            }
        } else if controller.history.entries.isEmpty {
            emptyMessage("Nog geen dictaten. Houd \(controller.settings.hotkey.label) ingedrukt en praat.") { EmptyView() }
        } else if filtered.isEmpty {
            emptyMessage("Niets gevonden voor \u{201C}\(query)\u{201D}.") { EmptyView() }
        } else {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            DashboardRow(entry: entry, controller: controller)
                        }
                    } header: {
                        Text(group.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
        }
    }

    private func emptyMessage(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            action()
        }
        .padding(.vertical, 18)
    }
}

private struct DashboardRow: View {
    let entry: HistoryEntry
    let controller: AppController
    @State private var hovering = false
    @State private var copied = false
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(entry.date.formatted(.dateTime.hour().minute().locale(.dutch)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 13.5))
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600, alignment: .leading)
                if let app = entry.appName {
                    Text(app)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                RowIconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: "Kopieer") {
                    controller.copyToClipboard(entry.text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                }
                RowIconButton(symbol: "trash", label: "Verwijder") {
                    controller.history.remove(entry.id)
                }
            }
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { expanded.toggle() }
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

struct RowIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
