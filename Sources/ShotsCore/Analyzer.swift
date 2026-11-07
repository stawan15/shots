import AppKit
import Foundation
import Vision

public struct Classification {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// Everything Vision can tell us about one image, without touching the file.
public struct ImageFacts {
    public let url: URL
    public let width: Int
    public let height: Int
    /// OCR lines already sorted in reading order (top to bottom, left to right).
    public let lines: [String]
    public let classes: [Classification]
    public let isScreenshot: Bool
    public let creationDate: Date

    public var text: String { lines.joined(separator: "\n").lowercased() }

    public func contains(_ needle: String) -> Bool { text.contains(needle.lowercased()) }

    public func firstLine(where predicate: (String) -> Bool) -> String? {
        lines.first(where: predicate)
    }

    /// Most specific scene label, skipping labels that describe "this is a picture"
    /// rather than "this is a picture of X".
    public init(
        url: URL, width: Int, height: Int, lines: [String],
        classes: [Classification], isScreenshot: Bool, creationDate: Date
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.lines = lines
        self.classes = classes
        self.isScreenshot = isScreenshot
        self.creationDate = creationDate
    }

    public var sceneLabel: String? {
        let boring: Set<String> = [
            "screenshot", "document", "text", "design", "graphic_design", "font",
            "rectangle", "paper", "white", "black", "pattern", "art", "poster",
            "webpage", "website", "menu", "display", "monitor", "television",
        ]
        return classes.first { $0.confidence > 0.12 && !boring.contains($0.label) }?.label
    }
}

public enum VisionError: Error, CustomStringConvertible {
    case unreadable(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): return "cannot decode image: \(url.path)"
        }
    }
}

public func analyze(_ url: URL, languages: [String]) throws -> ImageFacts {
    guard
        let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { throw VisionError.unreadable(url) }

    let ocr = VNRecognizeTextRequest()
    ocr.recognitionLevel = .accurate
    ocr.recognitionLanguages = languages
    ocr.usesLanguageCorrection = true

    let classifier = VNClassifyImageRequest()

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([ocr, classifier])

    let observations = (ocr.results ?? []).sorted { lhs, rhs in
        let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
        if abs(dy) > 0.012 { return dy > 0 }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
    let classes = (classifier.results ?? [])
        .map { Classification(label: $0.identifier, confidence: Double($0.confidence)) }

    let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
        ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? Date()

    let looksLikeScreenshot = classes.contains {
        $0.label == "screenshot" && $0.confidence > 0.4
    }

    return ImageFacts(
        url: url,
        width: cgImage.width,
        height: cgImage.height,
        lines: lines,
        classes: classes,
        isScreenshot: looksLikeScreenshot,
        creationDate: created
    )
}

public func analyzeAll(_ urls: [URL], languages: [String], progress: ((Int, Int) -> Void)? = nil) -> [(URL, Result<ImageFacts, Error>)] {
    var results = [Result<ImageFacts, Error>?](repeating: nil, count: urls.count)
    let lock = NSLock()
    var done = 0

    DispatchQueue.concurrentPerform(iterations: urls.count) { index in
        let outcome = Result { try analyze(urls[index], languages: languages) }
        lock.lock()
        results[index] = outcome
        done += 1
        let current = done
        lock.unlock()
        progress?(current, urls.count)
    }

    return zip(urls, results).map { ($0, $1 ?? .failure(VisionError.unreadable($0))) }
}
