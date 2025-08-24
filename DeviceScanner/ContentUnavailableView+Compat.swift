//
//  ContentUnavailableView+Compat.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import SwiftUI

struct FriendlyUnavailableView: View {
    let title: String
    let systemImage: String
    let description: Text

    init(title: String, systemImage: String = "photo.on.rectangle.angled", description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .bold()
            description
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6,6]))
                .foregroundStyle(.quaternary)
        )
        .padding(24)
    }
}
