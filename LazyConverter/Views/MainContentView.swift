//
//  MainContentView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI
import AVFoundation
import AVKit

struct MainContentView: View {
    @EnvironmentObject var lang: LanguageManager
    @StateObject private var viewModel = VideoConversionViewModel()
    
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                HeaderView()
                    .padding(.leading, 8)
                
                Divider()
                    .padding(.vertical, 4)
                
                // Layout principal: Left (Video) | Right (Settings)
                HStack(spacing: 24) {
                    // PANEL IZQUIERDO: Video Preview o Drag & Drop con Scroll
                    ScrollView {
                        VideoPanel(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    // PANEL DERECHO: Todas las configuraciones con Scroll
                    ScrollView {
                        SettingsPanel(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                BottomControlsPanel(viewModel: viewModel)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
            }
            .padding(12)
            .onAppear {
                viewModel.setLanguageManager(lang)
            }
            .task {
                        await viewModel.checkForUpdates()
            }
            .alert(lang.t("update.title"), isPresented: $viewModel.showUpdateDialog) {
                        Button(lang.t("update.download")) {
                            if let urlString = viewModel.latestDownloadURL,
                               let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(lang.t("update.cancel"), role: .cancel) { }
                    } message: {
                        Text(lang.t("update.message"))
                    }
        }
    }
}

#Preview {
    MainContentView()
        .environmentObject(LanguageManager())
}
