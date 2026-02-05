//
//  CustomButtonStyle.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 26/12/25.
//

import SwiftUI


struct CustomButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color.opacity(0.7))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
