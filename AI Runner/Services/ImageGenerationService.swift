//
//  ImageGenerationService.swift
//  AI Runner
//

import Foundation
import UIKit

/// Text-to-image through the Hugging Face Inference API.
///
/// A local GGUF model cannot paint pictures, so image generation only works
/// when the AI backend supports it — which here means the Hugging Face
/// Inference API with the user's token.
struct ImageGenerationService {
    enum ImageError: LocalizedError {
        case noToken
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Image generation needs a Hugging Face token. Add one in Settings."
            case .unsupported(let message):
                return message
            }
        }
    }

    /// Generates an image and returns it, or throws a readable error.
    func generate(prompt: String, model: String, token: String?) async throws -> UIImage {
        guard let token, !token.isEmpty else {
            throw ImageError.noToken
        }

        guard let url = URL(string: "https://router.huggingface.co/hf-inference/models/\(model)") else {
            throw ImageError.unsupported("Invalid image model name: \(model)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["inputs": prompt])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImageError.unsupported("No response from Hugging Face")
        }

        if (200..<300).contains(http.statusCode), let image = UIImage(data: data) {
            return image
        }

        // Hugging Face returns a JSON error for unsupported or loading models.
        let message = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { $0 as? [String: Any] }
            .flatMap { $0["error"] as? String }
            ?? "Hugging Face returned status \(http.statusCode). The model may not support text-to-image inference."
        throw ImageError.unsupported(message)
    }
}