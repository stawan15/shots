import AppKit
import Foundation

/// Efficient small previews: decode straight to thumbnail size instead of loading
/// a full 6K screenshot into memory for every row.
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL, size: CGFloat = 96) -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size * 2,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        cache.setObject(image, forKey: key)
        return image
    }
}
