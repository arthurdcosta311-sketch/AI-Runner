//
//  Color+App.swift
//  AI Runner
//

import SwiftUI

extension Color {
    /// The app's purple accent. It follows the AccentColor asset, so light and dark mode both stay purple.
    static var appPurple: Color { .accentColor }
}

extension ShapeStyle where Self == Color {
    static var appPurple: Color { .appPurple }
}
