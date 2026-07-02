import SwiftUI

/// SwiftUI view that parses Claude-generated markdown into typed
/// blocks and renders each block with the same visual hierarchy our
/// email templates use:
///
/// - `#`   → big white title
/// - `##`  → red uppercase divider bar (matches email h2)
/// - `###` → gold subheader (matches email h3)
/// - blockquote → emerald-tinted callout
/// - paragraph → body text with `**bold**` inline + paragraph spacing
///
/// Replaces the old `AttributedString(markdown:)` pipeline, which
/// collapsed every heading into a same-size bold line and produced
/// the wall-of-text that landed in the inbox.
///
/// Body string is run through `MarkdownReflow.paragraphs(_:)` first
/// so legacy stored content (no `\n\n` between sections) still
/// resolves cleanly.
struct StyledMarkdownView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(MarkdownReflow.paragraphs(markdown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .h1(let text):
            Text(text)
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .padding(.top, 12)
                .padding(.bottom, 8)

        case .h2(let text):
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(XomperColors.errorRed)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                Text(text.uppercased())
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(XomperColors.errorRed)
                    .tracking(2)
                    .padding(.top, 12)
            }
            .padding(.top, 28)
            .padding(.bottom, 10)

        case .h3(let text):
            Text(text)
                .font(.headline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .padding(.top, 14)
                .padding(.bottom, 4)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(XomperColors.championGold)
                    .frame(width: 3)
                inlineText(text)
                    .font(.body.italic())
                    .foregroundStyle(XomperColors.textSecondary)
            }
            .padding(.vertical, 8)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                inlineText(text)
                    .font(.body)
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.bottom, 8)

        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .lineSpacing(5)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// Inline `**bold**` rendering on top of plain text. Built as an
    /// `AttributedString` so we can mark just the bold spans with
    /// `.font(.body.weight(.bold))` and `.foregroundStyle(textPrimary)`
    /// without losing the surrounding paragraph styling.
    private func inlineText(_ raw: String) -> Text {
        var attr = AttributedString(raw)
        // Manually parse **...** pairs and apply bold.
        var working = raw
        var attrOut = AttributedString("")
        while let openRange = working.range(of: "**") {
            let before = String(working[working.startIndex..<openRange.lowerBound])
            attrOut.append(AttributedString(before))
            let afterOpen = working[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "**") {
                let boldText = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                var boldAttr = AttributedString(boldText)
                boldAttr.inlinePresentationIntent = .stronglyEmphasized
                attrOut.append(boldAttr)
                working = String(afterOpen[closeRange.upperBound...])
            } else {
                attrOut.append(AttributedString("**" + String(afterOpen)))
                working = ""
                break
            }
        }
        attrOut.append(AttributedString(working))
        attr = attrOut
        return Text(attr)
    }
}

// MARK: - Block model + parser

enum MarkdownBlock: Hashable {
    case h1(String)
    case h2(String)
    case h3(String)
    case quote(String)
    case bullet(String)
    case paragraph(String)
}

enum MarkdownBlockParser {
    /// Split `md` into typed blocks by `\n\n` separators. Each block's
    /// leading `# / ## / ### / >` token decides its type; everything
    /// else is a paragraph. Pre-reflowed content (via `MarkdownReflow`)
    /// is expected.
    static func parse(_ md: String) -> [MarkdownBlock] {
        let chunks = md.components(separatedBy: "\n\n")
        return chunks.compactMap { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("### ") {
                return .h3(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("## ") {
                return .h2(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("# ") {
                return .h1(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("> ") {
                return .quote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                // Collapse any wrapped continuation lines within the
                // bullet into a single spaced run, mirroring paragraph
                // handling below.
                let body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return .bullet(body.replacingOccurrences(of: "\n", with: " "))
            }
            // Paragraph — collapse internal newlines into spaces so a
            // wrapped paragraph from the AI doesn't render with hard
            // line breaks. Real paragraph breaks are at the `\n\n`
            // boundary above.
            let joined = trimmed.replacingOccurrences(of: "\n", with: " ")
            return .paragraph(joined)
        }
    }
}
