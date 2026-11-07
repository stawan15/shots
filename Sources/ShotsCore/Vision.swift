import Foundation
#if canImport(AppKit) && canImport(Vision)
import AppKit
import Vision

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

    // The classifier labels captures "screenshot" with high confidence; the
    // filename heuristic in Shots.looksLikeScreenshot covers the rest.
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

public func analyzeAll(
    _ urls: [URL], languages: [String], progress: ((Int, Int) -> Void)? = nil
) -> [(URL, Result<ImageFacts, Error>)] {
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

#else

/// Vision is macOS-only. On other platforms the analyzer reports every image as
/// unreadable so the pure naming logic can still be built and checked in CI.
public enum VisionError: Error, CustomStringConvertible {
    case unreadable(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): return "vision unavailable on this platform: \(url.path)"
        }
    }
}

public func analyze(_ url: URL, languages: [String]) throws -> ImageFacts {
    throw VisionError.unreadable(url)
}

public func analyzeAll(
    _ urls: [URL], languages: [String], progress: ((Int, Int) -> Void)? = nil
) -> [(URL, Result<ImageFacts, Error>)] {
    urls.map { ($0, .failure(VisionError.unreadable($0))) }
}

#endif
