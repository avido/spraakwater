import Foundation

/// Sends a recording to an OpenAI-compatible transcription endpoint (OpenAI or Groq).
struct Transcriber {
    func transcribe(
        fileURL: URL,
        provider: TranscriptionProvider,
        apiKey: String,
        language: DictationLanguage,
        vocabulary: [String]
    ) async throws -> String {
        var body = MultipartBody()
        body.field("model", provider.model)
        body.field("response_format", "json")
        body.field("temperature", "0")
        if let code = language.code {
            body.field("language", code)
        }
        if !vocabulary.isEmpty {
            // The prompt nudges the model towards these spellings.
            body.field("prompt", "Namen en termen: " + vocabulary.joined(separator: ", ") + ".")
        }
        body.file("file", filename: "opname.wav", mimeType: "audio/wav", content: try Data(contentsOf: fileURL))

        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body.finalized())
        try validate(response, data: data, service: provider.shortName)

        struct Result: Decodable { let text: String }
        guard let result = try? JSONDecoder().decode(Result.self, from: data) else {
            throw DicteerError.invalidResponse(service: provider.shortName)
        }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
