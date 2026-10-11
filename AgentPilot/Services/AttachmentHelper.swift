import UIKit
import ImageIO

/// 待发送的文件（图片之外的文件）
struct OutgoingFile: Identifiable {
    let id = UUID()
    var name: String
    var mimeType: String
    var data: Data
}

enum AttachmentHelper {
    /// 中继单条消息体上限 256 KB，base64 膨胀约 33%，内联原始数据控制在 150 KB 内
    static let maxInlineDataBytes = 150_000

    /// 压缩图片到指定体积以下（逐步降尺寸 + 降质量）
    static func compressImage(_ image: UIImage, maxBytes: Int = maxInlineDataBytes) -> Data {
        var quality: CGFloat = 0.8
        var maxDim: CGFloat = 1600
        var cur = image
        var data = cur.jpegData(compressionQuality: quality) ?? Data()

        while data.count > maxBytes && (maxDim > 320 || quality > 0.2) {
            if maxDim > 320 {
                maxDim = max(maxDim * 0.7, 320)
                cur = resize(cur, maxDim: maxDim)
            } else {
                quality = max(quality - 0.15, 0.2)
            }
            data = cur.jpegData(compressionQuality: quality) ?? data
        }
        return data
    }

    static func resize(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDim else { return image }
        let scale = maxDim / largest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func mime(forFilename name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }

    static func readableSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    static func imageSize(for data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        return w > 0 && h > 0 ? CGSize(width: w, height: h) : nil
    }
}
