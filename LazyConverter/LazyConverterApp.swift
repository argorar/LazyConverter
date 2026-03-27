//
//  LazyConverterApp.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 23/12/25.
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers
import AVFoundation
import AVKit

@main
struct LazyConverterApp: App {
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var watermarkPreferencesManager = WatermarkPreferencesManager()
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(languageManager)
                .environmentObject(themeManager)
                .environmentObject(watermarkPreferencesManager)
                .preferredColorScheme(themeManager.theme.colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

final class LanguageManager: ObservableObject {
    @AppStorage("selectedLanguage") private var storedLanguageData: Data = Data()
    
    @Published var language: AppLanguage = .en {
        didSet {
            reloadBundle()
        }
    }

    @Published private(set) var bundle: Bundle = .main

    init() {
        if !storedLanguageData.isEmpty,
            let decoded = try? JSONDecoder().decode(AppLanguage.self, from: storedLanguageData) {
            language = decoded
        }
        reloadBundle()
    }
    
    func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    func saveUserLanguage() {
        if let data = try? JSONEncoder().encode(language) {
            storedLanguageData = data
        }
    }
    
    private func reloadBundle() {
        // Compute the new bundle synchronously
        let newBundle: Bundle
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            newBundle = langBundle
        } else {
            newBundle = .main
        }

        // Publish the change asynchronously on the main queue to avoid publishing during view updates
        DispatchQueue.main.async { [weak self] in
            self?.bundle = newBundle
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case dark
    case light
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum AppSurfaceStyle: String, CaseIterable, Identifiable, Codable {
    case glass
    case normal

    var id: String { rawValue }
}

final class ThemeManager: ObservableObject {
    @AppStorage("selectedTheme") private var storedThemeData: Data = Data()
    @AppStorage("selectedSurfaceStyle") private var storedSurfaceStyleData: Data = Data()
    
    @Published var theme: AppTheme = .dark {
        didSet {
            publishTheme()
        }
    }

    @Published var surfaceStyle: AppSurfaceStyle = .glass {
        didSet {
            saveSurfaceStyle()
        }
    }

    init() {
        if !storedThemeData.isEmpty,
           let decoded = try? JSONDecoder().decode(AppTheme.self, from: storedThemeData) {
            theme = decoded
        } else {
            theme = .dark
        }

        if !storedSurfaceStyleData.isEmpty,
           let decodedStyle = try? JSONDecoder().decode(AppSurfaceStyle.self, from: storedSurfaceStyleData) {
            surfaceStyle = decodedStyle
        } else {
            surfaceStyle = .glass
        }
        publishTheme()
    }
    
    func saveUserTheme() {
        if let data = try? JSONEncoder().encode(theme) {
            storedThemeData = data
        }
    }

    func saveSurfaceStyle() {
        if let data = try? JSONEncoder().encode(surfaceStyle) {
            storedSurfaceStyleData = data
        }
    }

    private func publishTheme() {}
}

final class WatermarkPreferencesManager: ObservableObject {
    @AppStorage("defaultWatermarkText") private var storedDefaultWatermarkText: String = ""
    @AppStorage("defaultWatermarkFontName") private var storedDefaultWatermarkFontName: String = WatermarkConfig.systemFontToken

    @Published var defaultWatermarkText: String = "" {
        didSet {
            storedDefaultWatermarkText = defaultWatermarkText
        }
    }

    @Published var defaultWatermarkFontName: String = WatermarkConfig.systemFontToken {
        didSet {
            storedDefaultWatermarkFontName = defaultWatermarkFontName
        }
    }

    init() {
        defaultWatermarkText = storedDefaultWatermarkText
        defaultWatermarkFontName = storedDefaultWatermarkFontName
    }
}

#Preview {
    MainContentView()
        .environmentObject(LanguageManager())
        .environmentObject(ThemeManager())
        .environmentObject(WatermarkPreferencesManager())
}
