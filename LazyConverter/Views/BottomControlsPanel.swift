//
//  BottomControlsPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 3/01/26.
//

import SwiftUI

struct BottomControlsPanel: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    
    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.red)
                        
                        Spacer()
                        
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Progress Bar
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lang.t("progress.title"))
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(viewModel.progress))%")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.accentColor)
                    }
                    
                    ProgressView(value: viewModel.progress, total: 100)
                        .tint(.accentColor)
                        .opacity(viewModel.isProcessing ? 1 : 0)
                        .frame(height: 12)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isProcessing)
                    
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                        .opacity(viewModel.isProcessing ? 1 : 0)
                        .frame(height: 16)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.statusMessage)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Success Message
            if viewModel.progress == 100 && !viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.green)
                        
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            if !viewModel.statusMessage.isEmpty &&
               viewModel.statusMessage.contains(lang.t("queue.added.multiple").split(separator: " ").first!) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "plus.rectangle.on.rectangle.fill")
                            .foregroundColor(.accentColor)
                        
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Button(action: { viewModel.statusMessage = "" }) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.addCurrentVideoToQueue()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 13))
                        Text(lang.t("queue.add"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .separatorColor).opacity(0.5))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedFileURL == nil || viewModel.isProcessing)
                .help(lang.t("queue.add.tooltip"))
                
                
                Button(action: {
                    viewModel.showQueueWindow.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13))
                        Text(lang.t("queue.show"))
                            .font(.system(size: 13, weight: .medium))
                        
                        if viewModel.queueManager.queue.count > 0 {
                            Text("(\(viewModel.queueManager.queue.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        viewModel.queueManager.queue.isEmpty
                            ? Color(nsColor: .separatorColor).opacity(0.5)
                            : Color.accentColor.opacity(0.15)
                    )
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(lang.t("queue.show.tooltip"))
                
                Button(action: { viewModel.clearSelection() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                        Text(lang.t("action.clear"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .separatorColor).opacity(0.5))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing)
                
                Button(action: {
                    if viewModel.isProcessing {
                        viewModel.stopConversion()
                    } else {
                        viewModel.startConversion()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isProcessing ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                        Text(viewModel.isProcessing ? lang.t("action.stop") : lang.t("action.convert"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        viewModel.canConvert || viewModel.isProcessing
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.5)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $viewModel.showQueueWindow) {
            QueueView(queueManager: viewModel.queueManager)
                .environmentObject(lang)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}

