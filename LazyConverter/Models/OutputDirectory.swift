//
//  OutputDirectory.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 10/02/26.
//

import Foundation

enum OutputDirectory: String, CaseIterable, Identifiable, Codable {
    case downloads
    case documents
    case movies
    case desktop
    
    var id: String { rawValue }
    
    func resolveURL() -> URL {
        let fm = FileManager.default
        switch self {
        case .downloads:
            return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        case .documents:
            return fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        case .movies:
            return fm.urls(for: .moviesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        case .desktop:
            return fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        }
    }
}
