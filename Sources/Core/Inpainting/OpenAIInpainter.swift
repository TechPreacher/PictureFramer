import CoreGraphics
import Foundation

/// OpenAI Images Edits API with a true inpainting mask: transparent mask
/// pixels mark the region to repaint.
struct OpenAIInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gpt-image-1"

    /// gpt-image-1 accepts exactly these output sizes.
    private static let sizes = [
        CGSize(width: 1024, height: 1024),
        CGSize(width: 1536, height: 1024),
        CGSize(width: 1024, height: 1536),
    ]

    func uploadSize(for cropSize: CGSize) -> CGSize {
        guard cropSize.height > 0 else { return Self.sizes[0] }
        let aspect = cropSize.width / cropSize.height
        return Self.sizes.min {
            abs(log($0.width / $0.height) - log(aspect))
                < abs(log($1.width / $1.height) - log(aspect))
        }!
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        guard let imagePNG = pngData(from: image),
              let maskPNG = Self.transparentWhereWhitePNG(from: mask) else {
            throw InpaintingError.renderingFailed
        }
        var form = MultipartForm()
        form.addField(name: "model", value: model)
        form.addField(name: "prompt", value: InpaintingPrompt.text)
        form.addField(name: "size", value: "\(image.width)x\(image.height)")
        form.addFile(name: "image[]", filename: "image.png", mimeType: "image/png", data: imagePNG)
        form.addFile(name: "mask", filename: "mask.png", mimeType: "image/png", data: maskPNG)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response: response, data: data)
        struct Payload: Decodable {
            struct Item: Decodable { let b64_json: String }
            let data: [Item]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let b64 = payload.data.first?.b64_json,
              let imageData = Data(base64Encoded: b64),
              let result = cgImage(fromEncoded: imageData) else {
            throw InpaintingError.invalidResponse
        }
        return result
    }

    /// OpenAI marks repaint regions with TRANSPARENT mask pixels; our masks
    /// use white. Convert: alpha = 255 - grayValue.
    static func transparentWhereWhitePNG(from mask: CGImage) -> Data? {
        let width = mask.width
        let height = mask.height
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let grayContext = CGContext(
            data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        grayContext.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4 + 3] = 255 &- gray[i]   // premultiplied black + inverse alpha
        }
        let out: CGImage? = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        return out.flatMap(pngData(from:))
    }

    static func checkStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw InpaintingError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw InpaintingError.invalidKey
        case 429:
            throw InpaintingError.rateLimited
        default:
            struct ErrorPayload: Decodable {
                struct Inner: Decodable { let message: String }
                let error: Inner
            }
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?
                .error.message ?? "HTTP \(http.statusCode)"
            throw InpaintingError.server(message)
        }
    }
}

/// Minimal multipart/form-data builder.
struct MultipartForm {
    let boundary = "PictureFramer-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }
}
