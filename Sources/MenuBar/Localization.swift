import Foundation
import CLIProxyBarCore
public extension String {
 func localized() -> String { NSLocalizedString(self, comment: "") }
 func localizedStatic() -> String { localized() }
}
public extension AppLanguage {
    var displayName: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        case .chinese: "简体中文"
        case .french: "Français"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .vietnamese: "🇻🇳"
        case .chinese: "🇨🇳"
        case .french: "🇫🇷"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
