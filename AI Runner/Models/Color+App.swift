//
//  Color+App.swift
//  AI Runner
//

import SwiftUI

extension Color {
    /// The app's signature amber, matching the smiley icon.
    static let appAmber = Color(red: 1.0, green: 0.78, blue: 0.18)
}

extension ShapeStyle where Self == Color {
    static var appAmber: Color { .appAmber }
}