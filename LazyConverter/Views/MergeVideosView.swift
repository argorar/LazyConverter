//
//  MergeVideosView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 22/04/26.
//

import SwiftUI
import AVFoundation

struct MergeVideosView: View {
    @EnvironmentObject var lang: LanguageManager
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = MergeVideosViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(lang.t("merge.title"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    if !viewModel.isProcessing {
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing)
            }
            .padding(.top, 10)
            
            // List of selected videos
            VStack(alignment: .leading, spacing: 8) {
                Text(lang.t("merge.list_title"))
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if viewModel.selectedVideoURLs.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "film.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.bottom, 8)
                        Text(lang.t("merge.empty_state"))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                } else {
                    List {
                        ForEach(Array(viewModel.selectedVideoURLs.enumerated()), id: \.offset) { index, url in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                HStack(spacing: 12) {
                                    Button(action: { viewModel.moveUp(index: index) }) {
                                        Image(systemName: "arrow.up")
                                            .foregroundColor(index > 0 ? .primary : .secondary.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == 0 || viewModel.isProcessing)
                                    
                                    Button(action: { viewModel.moveDown(index: index) }) {
                                        Image(systemName: "arrow.down")
                                            .foregroundColor(index < viewModel.selectedVideoURLs.count - 1 ? .primary : .secondary.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == viewModel.selectedVideoURLs.count - 1 || viewModel.isProcessing)
                                    
                                    Button(action: { viewModel.removeVideo(at: index) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(viewModel.isProcessing)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 200)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            
            // Error / Progress Display
            if let errorMsg = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            if viewModel.isProcessing || viewModel.progress == 100 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.progress == 100 ? .green : .accentColor)
                        Spacer()
                        if viewModel.isProcessing {
                            Text("\(Int(viewModel.progress))%")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    if viewModel.isProcessing {
                        ProgressView(value: viewModel.progress, total: 100)
                            .tint(.accentColor)
                    }
                }
                .padding(10)
                .background(viewModel.progress == 100 ? Color.green.opacity(0.1) : Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Actions
            HStack(spacing: 16) {
                Button(action: {
                    viewModel.openFileSelector()
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text(lang.t("merge.add_button"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing)
                
                Button(action: {
                    viewModel.startMerge()
                }) {
                    HStack {
                        Image(systemName: "film.stack")
                        Text(lang.t("merge.start_button"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(viewModel.selectedVideoURLs.count > 1 ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedVideoURLs.count < 2 || viewModel.isProcessing)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
        .onAppear {
            viewModel.setLanguageManager(lang)
        }
    }
}
