//
//  FlowLayout.swift
//  Jotley
//
//  Flow layout and preference keys extracted from NoteDetailPlaceholderView+Body.swift
//

import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, element) in result.rows.enumerated() {
            var x = bounds.minX
            for (subviewIndex, subview) in zip(element.range, subviews[element.range]) {
                let width = result.widths[subviewIndex]
                let itemSize = result.sizes[subviewIndex]
                // Center each item vertically within the row
                let yOffset = bounds.minY + result.yOffsets[index] + (element.height - itemSize.height) / 2
                subview.place(at: CGPoint(x: x, y: yOffset),
                             proposal: ProposedViewSize(width: width, height: itemSize.height))
                x += width + spacing
            }
        }
    }

    struct FlowResult {
        var rows: [(range: Range<Int>, height: CGFloat)] = []
        var yOffsets: [CGFloat] = []
        var widths: [CGFloat] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            var rangeStart = 0

            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)
                widths.append(size.width)
                sizes.append(size)

                if x + size.width > width && rangeStart < index {
                    rows.append((rangeStart..<index, maxHeight))
                    yOffsets.append(y)
                    y += maxHeight + spacing
                    x = 0
                    maxHeight = 0
                    rangeStart = index
                }

                x += size.width + spacing
                maxHeight = max(maxHeight, size.height)
            }

            if rangeStart < subviews.count {
                rows.append((rangeStart..<subviews.count, maxHeight))
                yOffsets.append(y)
                y += maxHeight
            }

            self.size = CGSize(width: width, height: y)
        }
    }
}
