//
//  QueueView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var queueManager: QueueManager
    @EnvironmentObject var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.accentColor)
                Text(lang.t("queue.title"))
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Text("\(queueManager.queue.count) items")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(lang.t("queue.close"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Queue List
            if queueManager.queue.isEmpty {
                emptyQueueView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(queueManager.queue.enumerated()), id: \.element.id) { index, item in
                            QueueItemRow(
                                item: item,
                                index: index,
                                isCurrent: queueManager.currentItemIndex == index,
                                onRemove: { queueManager.removeItem(at: index) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
            
            Divider()
            
            // Controls
            HStack(spacing: 12) {
                // Global progress
                if queueManager.isProcessing {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(lang.t("queue.progress"))
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(queueManager.globalProgress))%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        ProgressView(value: queueManager.globalProgress, total: 100)
                            .progressViewStyle(.linear)
                    }
                }
                
                Spacer()
                
                // Botón Clear All
                Button(action: {
                    queueManager.clearAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                        Text(lang.t("queue.clearAll"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(queueManager.queue.isEmpty || queueManager.isProcessing)
                .help(lang.t("queue.clearAll.tooltip"))
                
                // Buttons
                Button(action: { queueManager.clearCompleted() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                        Text(lang.t("queue.clear"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .separatorColor).opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(queueManager.queue.filter { $0.status == .completed }.isEmpty)
                .help(lang.t("queue.clear.tooltip"))
                
                if queueManager.isProcessing {
                    Button(action: { queueManager.pauseQueue() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "pause.fill")
                            Text(lang.t("queue.pause"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Button(action: {
                        Task {
                            await queueManager.startQueue()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text(lang.t("queue.start"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queueManager.queue.filter { $0.status == .pending }.isEmpty)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(lang.t("queue.empty"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QueueItemRow: View {
    let item: QueueItem
    let index: Int
    let isCurrent: Bool
    let onRemove: () -> Void
    @EnvironmentObject var lang: LanguageManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: item.status.icon)
                .font(.system(size: 16))
                .foregroundColor(item.status.color)
                .frame(width: 24)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.format.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(item.resolution.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if let error = item.error {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Progress
            if item.status == .converting {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(item.progress))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                    ProgressView(value: item.progress, total: 100)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                }
            }
            
            // Remove button
            if item.status != .converting {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
