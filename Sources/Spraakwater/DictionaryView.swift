import SwiftUI

/// The word list: names and terms the speech recognition and the cleanup should spell correctly.
struct DictionaryView: View {
    /// Only this many terms fit in the hint that goes to the speech recognition.
    private static let transcriptionLimit = 60

    @Bindable var settings: Settings
    @State private var query = ""

    private var allWords: [String] {
        var seen = Set<String>()
        return settings.vocabularyWords.filter { seen.insert($0.lowercased()).inserted }
    }

    private var shownWords: [String] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return allWords }
        return allWords.filter { $0.localizedStandardContains(term) }
    }

    var body: some View {
        PageContainer {
            PageHeader(
                title: "Woordenlijst",
                subtitle: "Namen en vaktermen die vaak verkeerd verstaan worden. Spraakwater schrijft ze daarna goed."
            )

            InlineAddField(
                prompt: "Nieuw woord of term, meerdere gescheiden door een komma",
                buttonTitle: "Toevoegen"
            ) { settings.addTerms($0) }

            HStack {
                Text(allWords.count == 1 ? "1 woord" : "\(allWords.count) woorden")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                if !allWords.isEmpty {
                    SearchField(text: $query, prompt: "Zoek in de woordenlijst")
                }
            }

            if allWords.isEmpty {
                Text("Nog geen woorden. Voeg namen toe die Spraakwater vaak fout schrijft, zoals de naam van een collega of een product.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if shownWords.isEmpty {
                Text("Niets gevonden voor \u{201C}\(query)\u{201D}.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(shownWords, id: \.self) { word in
                        TermChip(term: word) { settings.removeTerm(word) }
                    }
                }
            }

            if allWords.count > Self.transcriptionLimit {
                Text("Bij het verstaan worden de nieuwste \(Self.transcriptionLimit) woorden meegestuurd. Bij het opruimen gebruikt Claude ze allemaal.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TermChip: View {
    let term: String
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(term)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 4)
            RowIconButton(symbol: "xmark", label: "Verwijder \(term)", action: onDelete)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(hovering ? 0.05 : 0.025)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}
