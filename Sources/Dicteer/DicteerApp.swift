import SwiftUI

@main
struct DicteerApp: App {
    private let controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.iconName)
        }
    }
}

struct MenuContent: View {
    let controller: AppController

    var body: some View {
        Text(controller.statusText)

        if let message = controller.message {
            Text(message)
        }

        Divider()

        Button("Kopieer laatste tekst") { controller.copyLastText() }
            .disabled(controller.lastText == nil)
        Button("Instellingen...") { SettingsWindow.show() }
            .keyboardShortcut(",")

        Divider()

        Button("Afsluiten") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
