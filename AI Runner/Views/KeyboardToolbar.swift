//
//  KeyboardToolbar.swift
//  AI Runner
//

import SwiftUI
import UIKit

/// Closes the keyboard for whichever field is editing.
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil,
                                    from: nil,
                                    for: nil)
}

extension View {
    /// Puts a Hide Keyboard button on the bar above the keyboard. The bar shows
    /// only while a field is editing, which is exactly when the button is needed.
    func hideKeyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    dismissKeyboard()
                } label: {
                    Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                }
                .tint(.appPurple)
            }
        }
    }
}
