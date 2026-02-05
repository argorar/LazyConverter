//
//  CropOverlayView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 29/12/25.
//

import SwiftUI

struct CropOverlayView: View {
    @Binding var cropRect: CGRect
    let videoSize: CGSize
    let playerFrame: CGRect
    @FocusState private var isFocused: Bool

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight, body }
    
    private var arrowStep: CGFloat {
        let pixelsPerStep: CGFloat = 5  // Mover 5px por cada tecla
        return pixelsPerStep / videoSize.width  // Normalizado a 0-1
    }
    
    @GestureState private var dragOffset: CGSize = .zero
    @State private var baseCropRect: CGRect = .zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let videoFrame = calculateVideoFrame(videoSize: videoSize, playerFrame: playerFrame)
            let cropPixelRect = CGRect(
                x: cropRect.origin.x * videoFrame.width + videoFrame.minX,
                y: cropRect.origin.y * videoFrame.height + videoFrame.minY,
                width: cropRect.size.width * videoFrame.width,
                height: cropRect.size.height * videoFrame.height
            )

            ZStack {
                // Fondo oscuro SOLO en área del video, con hueco transparente en el recorte
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)
                    .overlay(
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: cropPixelRect.width, height: cropPixelRect.height)
                            .position(x: cropPixelRect.midX, y: cropPixelRect.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()

                // Borde del crop
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropPixelRect.width, height: cropPixelRect.height)
                    .position(x: cropPixelRect.midX, y: cropPixelRect.midY)

                // Handles
                handleView(corner: .topLeft, rect: cropPixelRect, videoFrame: videoFrame)
                handleView(corner: .topRight, rect: cropPixelRect, videoFrame: videoFrame)
                handleView(corner: .bottomLeft, rect: cropPixelRect, videoFrame: videoFrame)
                handleView(corner: .bottomRight, rect: cropPixelRect, videoFrame: videoFrame)

                // Cuerpo draggable
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: cropPixelRect.width - 8, height: cropPixelRect.height - 8)
                    .position(x: cropPixelRect.midX, y: cropPixelRect.midY)
                    .gesture(dragGesture(corner: .body, videoFrame: videoFrame))
                
                // Texto con dimensiones en píxeles
                VStack(spacing: 2) {
                    Text("\(Int(cropRect.width * videoSize.width)) × \(Int(cropRect.height * videoSize.height))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                }
                .position(x: cropPixelRect.midX, y: cropPixelRect.minY - 20)
            }
            .focusable(true)
            .focused($isFocused)
            .onAppear {
                isFocused = true
                baseCropRect = cropRect
            }
            .onChange(of: cropRect) { oldValue, newValue in
                if !isDragging {
                    baseCropRect = newValue
                }
            }
            .onKeyPress { key in
                guard key.modifiers.contains(.shift) else { return .ignored }
                switch key.key {
                case .leftArrow:
                    moveBy(dx: -arrowStep, dy: 0)
                    return .handled
                case .rightArrow:
                    moveBy(dx: arrowStep, dy: 0)
                    return .handled
                case .upArrow:
                    moveBy(dx: 0, dy: -arrowStep)
                    return .handled
                case .downArrow:
                    moveBy(dx: 0, dy: arrowStep)
                    return .handled
                default:
                    return .ignored
                }
            }
        }
    }

    private func calculateVideoFrame(videoSize: CGSize, playerFrame: CGRect) -> CGRect {
        let videoAspect = videoSize.width / videoSize.height
        let playerAspect = playerFrame.width / playerFrame.height
        
        let width, height: CGFloat
        if videoAspect > playerAspect {
            width = playerFrame.width
            height = width / videoAspect
        } else {
            height = playerFrame.height
            width = height * videoAspect
        }
        
        let x = (playerFrame.width - width) / 2
        let y = (playerFrame.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    @ViewBuilder
    private func handleView(corner: Corner, rect: CGRect, videoFrame: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
            )
            .position(cornerPosition(corner: corner, rect: rect))
            .gesture(dragGesture(corner: corner, videoFrame: videoFrame))
    }

    private func cornerPosition(corner: Corner, rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .body: return .zero
        }
    }

    private func dragGesture(corner: Corner, videoFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                isDragging = true
                
                let dxNorm = value.translation.width / videoFrame.width
                let dyNorm = value.translation.height / videoFrame.height
                
                handleDrag(
                    corner: corner,
                    dxNorm: dxNorm,
                    dyNorm: dyNorm,
                    baseRect: baseCropRect,
                    videoSize: videoSize
                )
            }
            .onEnded { _ in
                baseCropRect = cropRect
                isDragging = false
            }
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        var rect = cropRect
        rect.origin.x = max(0, min(1 - rect.size.width, rect.origin.x + dx))
        rect.origin.y = max(0, min(1 - rect.size.height, rect.origin.y + dy))
        DispatchQueue.main.async {
            cropRect = rect
            baseCropRect = rect
        }
    }

    private func handleDrag(corner: Corner, dxNorm: CGFloat, dyNorm: CGFloat, baseRect: CGRect, videoSize: CGSize) {
        var rect = baseRect
        
        let minPixels: CGFloat = 64
        let minSizeW = minPixels / videoSize.width
        let minSizeH = minPixels / videoSize.height

        switch corner {
        case .body:
            rect.origin.x += dxNorm
            rect.origin.y += dyNorm
            
        case .topLeft:
            let newX = baseRect.origin.x + dxNorm
            let newY = baseRect.origin.y + dyNorm
            let newW = baseRect.size.width - dxNorm
            let newH = baseRect.size.height - dyNorm
            
            if newW >= minSizeW && newH >= minSizeH {
                rect.origin.x = newX
                rect.origin.y = newY
                rect.size.width = newW
                rect.size.height = newH
            }
            
        case .topRight:
            let newY = baseRect.origin.y + dyNorm
            let newW = baseRect.size.width + dxNorm
            let newH = baseRect.size.height - dyNorm
            
            if newW >= minSizeW && newH >= minSizeH {
                rect.origin.y = newY
                rect.size.width = newW
                rect.size.height = newH
            }
            
        case .bottomLeft:
            let newX = baseRect.origin.x + dxNorm
            let newW = baseRect.size.width - dxNorm
            let newH = baseRect.size.height + dyNorm
            
            if newW >= minSizeW && newH >= minSizeH {
                rect.origin.x = newX
                rect.size.width = newW
                rect.size.height = newH
            }
            
        case .bottomRight:
            let newW = baseRect.size.width + dxNorm
            let newH = baseRect.size.height + dyNorm
            
            if newW >= minSizeW && newH >= minSizeH {
                rect.size.width = newW
                rect.size.height = newH
            }
        }

        rect.origin.x = max(0, min(1 - rect.size.width, rect.origin.x))
        rect.origin.y = max(0, min(1 - rect.size.height, rect.origin.y))
        rect.size.width = max(minSizeW, min(1 - rect.origin.x, rect.size.width))
        rect.size.height = max(minSizeH, min(1 - rect.origin.y, rect.size.height))

        DispatchQueue.main.async {
            cropRect = rect
        }
    }
}

