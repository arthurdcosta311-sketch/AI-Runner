//
//  AudioTranscriptionService.swift
//  AI Runner
//

import Foundation

/// Speech-to-text through the Hugging Face Inference API, with the user's token.
struct AudioTranscriptionService {
    enum AudioError: LocalizedError {
        case noToken
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Speech-to-text needs a Hugging Face token. Add one in Settings."
            case .failed(let message):
                return message
            }
        }
    }

    func transcribe(_ audio: Data, contentType: String, model: String, token: String?) async throws -> String {
        guard let token, !token.isEmpty else { throw AudioError.noToken }
        guard let url = URL(string: "https://router.huggingface.co/hf-inference/models/\(model)") else {
            throw AudioError.failed("Invalid speech model name: \(model)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = audio

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AudioError.failed("No response from Hugging Face")
        }

        if (200..<300).contains(http.statusCode),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text
        }

        let message = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { $0 as? [String: Any] }
            .flatMap { $0["error"] as? String }
            ?? "Hugging Face returned status \(http.statusCode). The model may not support speech-to-text."
        throw AudioError.failed(message)
    }
}
