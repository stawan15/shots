import Foundation

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

    /// Most specific scene label, skipping labels that describe "this is a picture"
    /// rather than "this is a picture of X".
    public var sceneLabel: String? {
        let boring: Set<String> = [
            "screenshot", "document", "text", "design", "graphic_design", "font",
            "rectangle", "paper", "white", "black", "pattern", "art", "poster",
            "webpage", "website", "menu", "display", "monitor", "television",
        ]
        return classes.first { $0.confidence > 0.12 && !boring.contains($0.label) }?.label
    }
}
