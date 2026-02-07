//
//  AppLanguage.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 3/01/26.
//


public enum AppLanguage: String, CaseIterable, Identifiable, Codable  {
    case es
    case en
    case de
    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        case .de: return "Deutsch"
        }
    }
}
