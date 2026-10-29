import Foundation

/// The product version. Semantic: major.minor.patch.
public enum ProductVersion {
    public static let semantic = "1.0.0"
    public static let author = "Aaqa Ishtyaq"
    public static let copyright = "© 2026 Aaqa Ishtyaq"
    public static let github = URL(string: "https://github.com/aaqaishtyaq/asciidraw")!
    public static let website = URL(string: "https://v1.aaqa.dev/asciidraw/")!

    public static var isSemantic: Bool {
        let parts = semantic.split(separator: ".")
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && Int(part) != nil
        }
    }
}
