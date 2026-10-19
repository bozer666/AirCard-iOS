import SwiftUI
import AirliftFFI

@main
struct AirCardApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var lang = LanguageManager.shared

    init() {
        // Route Rust tracing/idevice logs into the app's vm log array.
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            let line = String(cString: msg)
            DispatchQueue.main.async {
                AppViewModel.sharedLogSink?(line)
            }
        }, nil)

        // Point the sink at the vm once it's created (set in AppViewModel.init).
        // Ensure ALGetGrappaToken symbol is retained and linked into the binary
        _ = ALGetGrappaToken(0, 0, 0, nil, 0, nil, nil, 0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(lang)
                .environment(\.locale, lang.effectiveLocale)
                // Force a full view-tree rebuild on language change: this
                // guarantees every Text re-resolves its LocalizedStringKey
                // and every L10n.tr call re-evaluates, including inactive
                // TabView tabs. (State in vm/lang above is preserved.)
                .id("root-\(lang.effectiveCode)")
        }
    }
}

@_silgen_name("ALGetGrappaToken")
func ALGetGrappaToken(
    _ inVersion: UInt32,
    _ inDeviceType: UInt32,
    _ inProtocolVersion: UInt32,
    _ outBuf: UnsafeMutablePointer<UInt8>?,
    _ maxLen: Int,
    _ outLen: UnsafeMutablePointer<Int>?,
    _ errBuf: UnsafeMutablePointer<CChar>?,
    _ errLen: Int
) -> Int32

