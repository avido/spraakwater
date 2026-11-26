import Foundation

/// How the cleaned text should sound in a kind of app. Each style is a short instruction for the cleanup.
enum ToneStyle: String, CaseIterable, Identifiable, Codable {
    case standard
    case formal
    case excited
    case casual
    case technical
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standaard"
        case .formal: "Formeel"
        case .excited: "Enthousiast"
        case .casual: "Informeel"
        case .technical: "Technisch"
        case .custom: "Eigen toon"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Geen aanpassing, alleen opruimen"
        case .formal: "Volledige zinnen, volledige leestekens"
        case .excited: "Levendige woorden, meer uitroeptekens"
        case .casual: "Minder opmaak, lichte leestekens"
        case .technical: "Compact, namen en code letterlijk"
        case .custom: "Schrijf zelf een instructie"
        }
    }

    /// The instruction sent to the cleanup, empty when nothing should change.
    var instruction: String {
        switch self {
        case .standard, .custom: ""
        case .formal: "Zorgvuldig en beleefd, volledige zinnen en volledige leestekens, geen spreektaal."
        case .excited: "Levendig en enthousiast, expressieve woordkeus en wat meer uitroeptekens."
        case .casual: "Informeel en kort, zoals je in een chat typt. Minder opmaak en lichte leestekens, geen alinea's forceren."
        case .technical: "Technisch en compact. Laat bestandsnamen, commando's, functienamen en code letterlijk staan."
        }
    }

    /// What a category starts with before the user chooses.
    static func initial(for category: AppCategory) -> ToneStyle {
        switch category {
        case .mail: .formal
        case .chat: .casual
        case .code: .technical
        case .notes, .other: .standard
        }
    }
}

extension AppCategory {
    /// The kinds of app the user can set a tone for.
    static let styled: [AppCategory] = [.mail, .chat, .code, .notes]
}

/// Writing rules that apply everywhere, with ready-made suggestions the user can add with one click.
enum WritingRules {
    static let maxLength = 200

    static let defaults = [
        "Gebruik nooit een em-dash of en-dash.",
        "Zet in het Nederlands nooit een komma voor \"en\".",
        "Schrijf direct en nuchter, in \"je\"-vorm.",
    ]

    static let suggestions = [
        "Houd het kort en direct.",
        "Sla beleefdheidsfrasen over, zoals \"ik hoop dat het goed met je gaat\".",
        "Gebruik opsommingstekens spaarzaam.",
        "Gebruik \"je\" in plaats van \"u\".",
        "Gebruik geen emoji.",
    ] + defaults
}
