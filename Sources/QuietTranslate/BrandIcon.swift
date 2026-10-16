import AppKit

enum BrandIcon {
    static func image(size: CGFloat, monochrome: Bool = false) -> NSImage {
        let url = Bundle.module.url(forResource: monochrome ? "MenuBar-template" : "BrandIcon",
                                    withExtension: monochrome ? "pdf" : "png")
        let image = url.flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "QuietTranslate")
            ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        image.isTemplate = monochrome
        image.accessibilityDescription = "QuietTranslate"
        return image
    }
}
