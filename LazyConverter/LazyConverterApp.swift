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
    var body: some Scene {
        WindowGroup {
            let languageManager = LanguageManager()
            MainContentView()
                .environmentObject(languageManager)
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

#Preview {
    MainContentView()
}

