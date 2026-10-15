import AppKit

/// Shows the standard About window with Lumina's credits and license.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString(string: "Made with ❤️ by ", attributes: attributes)
        var link = attributes
        link[.link] = URL(string: "https://github.com/hectorgoan")!
        credits.append(NSAttributedString(string: "@hectorgoan", attributes: link))
        credits.append(NSAttributedString(string: "\nReleased under the MIT License.", attributes: attributes))
        return credits
    }
}
