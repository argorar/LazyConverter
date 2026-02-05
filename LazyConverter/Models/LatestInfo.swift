//
//  LatestInfo.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 2/01/26.
//

struct LatestInfo: Codable {
    let version: String
    let downloads: Downloads?
}

struct Downloads: Codable {
    let macosUniversal: MacOSDownload
    enum CodingKeys: String, CodingKey {
        case macosUniversal = "macos-universal"
    }
}

struct MacOSDownload: Codable {
    let url: String
}
