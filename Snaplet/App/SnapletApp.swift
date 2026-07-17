import SwiftUI

@main
struct SnapletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Snaplet is a menu-bar agent (LSUIElement); it presents no primary
        // window at launch. A Settings scene is the SwiftUI-idiomatic way to
        // declare an app with no default window. Menu-bar UI arrives in Wave 1.
        Settings {
            EmptyView()
        }
    }
}
