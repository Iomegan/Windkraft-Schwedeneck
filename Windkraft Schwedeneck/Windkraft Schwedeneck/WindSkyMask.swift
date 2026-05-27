//
//  WindSkyMask.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 21.05.26.
//

import ARKit
import CoreGraphics
import CoreVideo
import UIKit

struct WindSkyMask {
    let viewportSize: CGSize
    let skyRects: [CGRect]
    let sampleCount: Int
    let skySampleCount: Int

    static let unavailable = WindSkyMask(
        viewportSize: .zero,
        skyRects: [],
        sampleCount: 0,
        skySampleCount: 0
    )

    var hasSamples: Bool {
        sampleCount > 0
    }

    var hasSky: Bool {
        !skyRects.isEmpty
    }

    var coverageText: String {
        guard sampleCount > 0 else {
            return "--"
        }

        let percentage = Double(skySampleCount) / Double(sampleCount) * 100
        return percentage.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    func intersects(_ rect: CGRect) -> Bool {
        skyRects.contains { $0.intersects(rect) }
    }
}

enum WindSkyMaskBuilder {
    static func make(
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation
    ) -> WindSkyMask {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return .unavailable
        }

        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return .unavailable
        }

        let columns = 48
        let rows = max(36, Int((CGFloat(columns) * viewportSize.height / viewportSize.width).rounded()))
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let imageTransform = displayTransform.inverted()

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard
            let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self)
        else {
            return .unavailable
        }

        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        var candidates = Array(repeating: false, count: rows * columns)

        for row in 0..<rows {
            for column in 0..<columns {
                let viewPoint = CGPoint(
                    x: (CGFloat(column) + 0.5) / CGFloat(columns),
                    y: (CGFloat(row) + 0.5) / CGFloat(rows)
                )
                let imagePoint = viewPoint.applying(imageTransform)

                guard (0...1).contains(imagePoint.x), (0...1).contains(imagePoint.y) else {
                    continue
                }

                let lumaX = clampedIndex(Int((imagePoint.x * CGFloat(lumaWidth)).rounded()), upperBound: lumaWidth)
                let lumaY = clampedIndex(Int((imagePoint.y * CGFloat(lumaHeight)).rounded()), upperBound: lumaHeight)
                let chromaX = clampedIndex(Int((imagePoint.x * CGFloat(chromaWidth)).rounded()), upperBound: chromaWidth)
                let chromaY = clampedIndex(Int((imagePoint.y * CGFloat(chromaHeight)).rounded()), upperBound: chromaHeight)

                let y = lumaBase[lumaY * lumaBytesPerRow + lumaX]
                let chromaOffset = chromaY * chromaBytesPerRow + chromaX * 2
                let cb = chromaBase[chromaOffset]
                let cr = chromaBase[chromaOffset + 1]

                candidates[index(row: row, column: column, columns: columns)] = isSkyCandidate(y: y, cb: cb, cr: cr)
            }
        }

        let skyCells = connectedSkyCells(candidates: candidates, rows: rows, columns: columns)
        let rects = mergedRects(
            skyCells: skyCells,
            rows: rows,
            columns: columns,
            viewportSize: viewportSize
        )

        return WindSkyMask(
            viewportSize: viewportSize,
            skyRects: rects,
            sampleCount: rows * columns,
            skySampleCount: skyCells.filter { $0 }.count
        )
    }

    private static func isSkyCandidate(y: UInt8, cb: UInt8, cr: UInt8) -> Bool {
        let luma = Double(y) / 255
        let cbValue = Int(cb)
        let crValue = Int(cr)
        let chromaDistance = abs(cbValue - 128) + abs(crValue - 128)
        let blueSky = luma > 0.30 && cbValue > 134 && crValue < 134 && cbValue - crValue > 8
        let paleSky = luma > 0.46 && cbValue > 124 && crValue < 140 && cbValue >= crValue - 4
        let cloud = luma > 0.66 && chromaDistance < 34

        return blueSky || paleSky || cloud
    }

    private static func connectedSkyCells(candidates: [Bool], rows: Int, columns: Int) -> [Bool] {
        var skyCells = Array(repeating: false, count: candidates.count)
        var queue: [Int] = []
        var readIndex = 0
        let seedRows = min(rows, 3)

        for row in 0..<seedRows {
            for column in 0..<columns {
                let cellIndex = index(row: row, column: column, columns: columns)
                guard candidates[cellIndex], !skyCells[cellIndex] else {
                    continue
                }

                skyCells[cellIndex] = true
                queue.append(cellIndex)
            }
        }

        while readIndex < queue.count {
            let cellIndex = queue[readIndex]
            readIndex += 1

            let row = cellIndex / columns
            let column = cellIndex % columns
            let neighbors = [
                (row - 1, column),
                (row + 1, column),
                (row, column - 1),
                (row, column + 1)
            ]

            for (neighborRow, neighborColumn) in neighbors {
                guard
                    neighborRow >= 0,
                    neighborRow < rows,
                    neighborColumn >= 0,
                    neighborColumn < columns
                else {
                    continue
                }

                let neighborIndex = index(row: neighborRow, column: neighborColumn, columns: columns)
                guard candidates[neighborIndex], !skyCells[neighborIndex] else {
                    continue
                }

                skyCells[neighborIndex] = true
                queue.append(neighborIndex)
            }
        }

        return skyCells
    }

    private static func mergedRects(
        skyCells: [Bool],
        rows: Int,
        columns: Int,
        viewportSize: CGSize
    ) -> [CGRect] {
        let cellWidth = viewportSize.width / CGFloat(columns)
        let cellHeight = viewportSize.height / CGFloat(rows)
        var rects: [CGRect] = []

        for row in 0..<rows {
            var column = 0

            while column < columns {
                let cellIndex = index(row: row, column: column, columns: columns)
                guard skyCells[cellIndex] else {
                    column += 1
                    continue
                }

                let startColumn = column

                while column < columns, skyCells[index(row: row, column: column, columns: columns)] {
                    column += 1
                }

                rects.append(CGRect(
                    x: CGFloat(startColumn) * cellWidth - 0.5,
                    y: CGFloat(row) * cellHeight - 0.5,
                    width: CGFloat(column - startColumn) * cellWidth + 1,
                    height: cellHeight + 1
                ))
            }
        }

        return rects
    }

    private static func index(row: Int, column: Int, columns: Int) -> Int {
        row * columns + column
    }

    private static func clampedIndex(_ value: Int, upperBound: Int) -> Int {
        min(max(value, 0), max(upperBound - 1, 0))
    }
}
