//
//  FlowLayout.swift
//  Jotley
//
//  Wraps items into rows within the proposed width.
//

import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? .infinity, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, element) in result.rows.enumerated() {
            var x = bounds.minX
            for (subviewIndex, subview) in zip(element.range, subviews[element.range]) {
                let itemSize = result.sizes[subviewIndex]
                // Center each item vertically within the row
                let yOffset = bounds.minY + result.yOffsets[index] + (element.height - itemSize.height) / 2
                subview.place(at: CGPoint(x: x, y: yOffset),
                             proposal: ProposedViewSize(itemSize))
                x += itemSize.width + spacing
            }
        }
    }

    struct FlowResult {
        var rows: [(range: Range<Int>, height: CGFloat)] = []
        var yOffsets: [CGFloat] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            var maxWidth: CGFloat = 0
            var rangeStart = 0

            for (index, subview) in subviews.enumerated() {
                let idealSize = subview.sizeThatFits(.unspecified)
                let size = idealSize.width > width
                    ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    : idealSize
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
                maxWidth = max(maxWidth, x - spacing)
                maxHeight = max(maxHeight, size.height)
            }

            if rangeStart < subviews.count {
                rows.append((rangeStart..<subviews.count, maxHeight))
                yOffsets.append(y)
                y += maxHeight
            }

            self.size = CGSize(width: width.isFinite ? width : maxWidth, height: y)
        }
    }
}
