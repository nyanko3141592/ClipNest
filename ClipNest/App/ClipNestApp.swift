import SwiftUI

@main
struct ClipNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All windows are managed by AppDelegate via NSWindow
        Settings { EmptyView() }
    }
}
