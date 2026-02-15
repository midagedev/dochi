import AppKit
import Foundation

// MARK: - ImageAttachment (ViewModel, Non-Persistent)

/// Represents an image attached by the user before sending.
/// Used in the ViewModel for preview and management. Not persisted.
struct ImageAttachment: Identifiable, Sendable {
    let id: UUID
    let image: NSImage
    let data: Data
    let mimeType: String
    let fileName: String
    let originalSize: CGSize

    init(id: UUID = UUID(), image: NSImage, data: Data, mimeType: String, fileName: String = "image") {
        self.id = id
        self.image = image
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
        self.originalSize = image.size
    }

    /// Maximum number of images per message.
    static let maxCount = 4

    /// Maximum single image size in bytes (20 MB).
    static let maxSizeBytes = 20 * 1024 * 1024

    /// Maximum long edge in pixels for resizing.
    static let maxLongEdge: CGFloat = 2048

    /// JPEG compression quality for resized images.
    static let jpegQuality: CGFloat = 0.85

    /// Supported file extensions for image input.
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "tiff",
    ]
}

// MARK: - ImageContent (Message, Persistent)

/// Persistent image data stored in a Message.
/// Encoded as base64 for LLM API payloads.
struct ImageContent: Codable, Sendable, Equatable {
    let base64Data: String
    let mimeType: String
    let width: Int
    let height: Int
}

// MARK: - Image Processing Pipeline

enum ImageProcessor {
    /// Resize an NSImage so that its longest edge does not exceed `maxEdge`.
    /// Returns the resized image, or the original if already small enough.
    static func resize(_ image: NSImage, maxEdge: CGFloat = ImageAttachment.maxLongEdge) -> NSImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxEdge else { return image }

        let scale = maxEdge / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        resizedImage.unlockFocus()
        return resizedImage
    }

    /// Encode an NSImage to JPEG data with the given quality.
    /// Falls back to PNG if JPEG encoding fails.
    static func encodeToJPEG(_ image: NSImage, quality: CGFloat = ImageAttachment.jpegQuality) -> (data: Data, mimeType: String)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        if let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
            return (jpegData, "image/jpeg")
        }

        // Fallback to PNG
        if let pngData = bitmap.representation(using: .png, properties: [:]) {
            return (pngData, "image/png")
        }

        return nil
    }

    /// Encode an NSImage to PNG data.
    static func encodeToPNG(_ image: NSImage) -> (data: Data, mimeType: String)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (pngData, "image/png")
    }

    /// Full pipeline: resize + encode + base64.
    /// Returns nil if processing fails or image exceeds size limits.
    static func processForLLM(_ image: NSImage, preferPNG: Bool = false) -> ImageContent? {
        let resized = resize(image)

        let encoded: (data: Data, mimeType: String)?
        if preferPNG {
            encoded = encodeToPNG(resized)
        } else {
            encoded = encodeToJPEG(resized)
        }

        guard let (data, mimeType) = encoded else { return nil }
        guard data.count <= ImageAttachment.maxSizeBytes else { return nil }

        let base64 = data.base64EncodedString()
        return ImageContent(
            base64Data: base64,
            mimeType: mimeType,
            width: Int(resized.size.width),
            height: Int(resized.size.height)
        )
    }

    /// Create an ImageAttachment from an NSImage.
    static func createAttachment(from image: NSImage, fileName: String = "image") -> ImageAttachment? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: ImageAttachment.jpegQuality]) else {
            return nil
        }

        guard data.count <= ImageAttachment.maxSizeBytes else { return nil }

        return ImageAttachment(
            image: image,
            data: data,
            mimeType: "image/jpeg",
            fileName: fileName
        )
    }

    /// Create an ImageAttachment from file data with a known MIME type.
    static func createAttachment(from data: Data, mimeType: String, fileName: String = "image") -> ImageAttachment? {
        guard data.count <= ImageAttachment.maxSizeBytes else { return nil }
        guard let image = NSImage(data: data) else { return nil }

        return ImageAttachment(
            image: image,
            data: data,
            mimeType: mimeType,
            fileName: fileName
        )
    }

    /// Detect MIME type from file extension.
    static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        default: return "image/jpeg"
        }
    }
}
