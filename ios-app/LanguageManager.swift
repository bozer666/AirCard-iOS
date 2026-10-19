import SwiftUI

/// In-app UI language setting.
///
/// - "system": follow the iPhone language (Chinese → 中文, everything else → English)
/// - "en": force English
/// - "zh-Hans": force Simplified Chinese
///
/// The choice persists in UserDefaults and applies to every page immediately:
/// static `Text("…")` literals re-resolve through `.environment(\.locale, …)`,
/// while code-built strings go through `L10n.tr(_:_:)`.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    static let systemCode = "system"
    static let englishCode = "en"
    static let chineseCode = "zh-Hans"
    static let selectionKey = "aircard.language"

    /// "system" | "en" | "zh-Hans".
    /// NOTE: @Published + manual UserDefaults sync, NOT @AppStorage —
    /// @AppStorage inside an ObservableObject doesn't reliably emit
    /// objectWillChange, so the UI would only pick up the new language
    /// after a restart.
    @Published var selection: String = UserDefaults.standard.string(forKey: LanguageManager.selectionKey) ?? LanguageManager.systemCode {
        didSet {
            UserDefaults.standard.set(selection, forKey: Self.selectionKey)
        }
    }

    /// Effective lookup code: "en" or "zh-Hans".
    var effectiveCode: String {
        switch selection {
        case Self.englishCode: return Self.englishCode
        case Self.chineseCode: return Self.chineseCode
        default:
            let first = Locale.preferredLanguages.first ?? "en"
            return first.hasPrefix("zh") ? Self.chineseCode : Self.englishCode
        }
    }

    /// Locale pushed into the SwiftUI environment so `Text("…")` literals switch language live.
    var effectiveLocale: Locale {
        Locale(identifier: effectiveCode == Self.chineseCode ? "zh_Hans" : "en")
    }

    var isChinese: Bool { effectiveCode == Self.chineseCode }
}

/// Localized string lookup that honors the in-app language override
/// (unlike `NSLocalizedString`, which always follows the system language).
///
/// Keys are the English source strings (with `%@` / `%lld` for interpolated values),
/// exactly as they appear in `Localizable.strings`.
enum L10n {
    /// Resolve `key` for the current in-app language and format it with `args`.
    /// Missing keys fall back to the key itself (English).
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let code = LanguageManager.shared.effectiveCode
        let bundle: Bundle = {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
            return .main
        }()
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: LanguageManager.shared.effectiveLocale, arguments: args)
    }
}
