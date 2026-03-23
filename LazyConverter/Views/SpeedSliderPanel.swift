//
//  SpeedSliderPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import SwiftUI


struct SpeedSliderPanel: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var theme: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "speedometer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("speed.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            
            // Slider
            HStack {
                Text("\(Int(viewModel.speedPercent))%")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 50)
                
                Slider(value: $viewModel.speedPercent, in: 0...200, step: 5)
                    .accentColor(.accentColor)
                
                Text("200%")
                    .font(.system(size: 12))
                    .frame(width: 40)
            }
        }
        .padding(16)
        .adaptiveCard(
            useGlass: theme.surfaceStyle == .glass,
            cornerRadius: 12,
            material: .hudWindow,
            fallbackColor: Color(nsColor: .separatorColor),
            fallbackOpacity: 0.3
        )
    }
}
