//
//  HeaderView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var lang: LanguageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack( spacing: 0) {
                    Text(lang.t("app.name"))
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Text(lang.t("app.by"))
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    
                    Text(Bundle.main.appVersion)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .separatorColor))
                        .cornerRadius(6)
                }
            }
        }
    }
}
