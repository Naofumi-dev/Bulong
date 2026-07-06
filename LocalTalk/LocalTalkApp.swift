import SwiftUI

@main
struct LocalTalkApp: App {
    var body: some Scene {
        MenuBarExtra("LocalTalk", systemImage: "waveform") {
            Text("LocalTalk is running")
            Divider()
            Button("Quit LocalTalk") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
