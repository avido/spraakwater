import Foundation

enum DicteerError: LocalizedError {
    case recordingFailed
    case microphoneDenied
    case api(service: String, status: Int, message: String)
    case invalidResponse(service: String)

    var errorDescription: String? {
        switch self {
        case .recordingFailed:
            "De opname kon niet starten."
        case .microphoneDenied:
            "Geen toegang tot de microfoon. Zet dit aan bij Systeeminstellingen > Privacy en beveiliging > Microfoon."
        case let .api(service, status, message):
            "\(service) gaf fout \(status): \(message)"
        case let .invalidResponse(service):
            "\(service) gaf een antwoord dat niet te lezen is."
        }
    }
}

/// Builds a multipart/form-data body for the transcription upload.
struct MultipartBody {
    let boundary = "dicteer-\(UUID().uuidString)"
    private var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func field(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func file(_ name: String, filename: String, mimeType: String, content: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(content)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

/// Throws a readable error for non-2xx responses. Both APIs return {"error": {"message": ...}}.
func validate(_ response: URLResponse, data: Data, service: String) throws {
    guard let http = response as? HTTPURLResponse else {
        throw DicteerError.invalidResponse(service: service)
    }
    guard (200 ..< 300).contains(http.statusCode) else {
        struct Envelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
            ?? String(data: data, encoding: .utf8)?.prefix(200).description
            ?? "onbekende fout"
        throw DicteerError.api(service: service, status: http.statusCode, message: message)
    }
}
