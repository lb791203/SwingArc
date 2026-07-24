import Foundation

enum PPointCode: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"
    case p5 = "P5"
    case p6 = "P6"
    case p7 = "P7"
    case p8 = "P8"

    var id: String { rawValue }

    var ordinal: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

enum PPointSelectionSource: String, Codable, Equatable {
    case automatic
    case manual
    case unresolved
}

struct PPointSelection: Codable, Equatable {
    let code: PPointCode
    var sourceFrameIndex: Int?
    var suggestedSourceFrameIndex: Int?
    var source: PPointSelectionSource
}

struct PPointCorrectionState: Equatable {
    let frameCount: Int
    var selectedCode: PPointCode
    var currentSourceFrameIndex: Int
    private(set) var selections: [PPointSelection]

    init(
        frameCount: Int,
        predictedFrames: [PPointCode: Int],
        suggestedFrames: [PPointCode: Int],
        manualFrames: [PPointCode: Int]
    ) {
        self.frameCount = max(0, frameCount)
        self.selections = PPointCode.allCases.map { code in
            if let manual = Self.validFrame(manualFrames[code], frameCount: frameCount) {
                return PPointSelection(
                    code: code,
                    sourceFrameIndex: manual,
                    suggestedSourceFrameIndex: Self.validFrame(
                        predictedFrames[code] ?? suggestedFrames[code],
                        frameCount: frameCount
                    ),
                    source: .manual
                )
            }
            if let predicted = Self.validFrame(predictedFrames[code], frameCount: frameCount) {
                return PPointSelection(
                    code: code,
                    sourceFrameIndex: predicted,
                    suggestedSourceFrameIndex: predicted,
                    source: .automatic
                )
            }
            return PPointSelection(
                code: code,
                sourceFrameIndex: nil,
                suggestedSourceFrameIndex: Self.validFrame(
                    suggestedFrames[code],
                    frameCount: frameCount
                ),
                source: .unresolved
            )
        }

        let firstResolved = selections.first {
            $0.sourceFrameIndex != nil || $0.suggestedSourceFrameIndex != nil
        }
        self.selectedCode = firstResolved?.code ?? .p1
        self.currentSourceFrameIndex = firstResolved?.sourceFrameIndex
            ?? firstResolved?.suggestedSourceFrameIndex
            ?? 0
    }

    func selection(for code: PPointCode) -> PPointSelection {
        selections.first(where: { $0.code == code })
            ?? PPointSelection(
                code: code,
                sourceFrameIndex: nil,
                suggestedSourceFrameIndex: nil,
                source: .unresolved
            )
    }

    var orderedManualSelections: [PPointSelection] {
        selections
            .filter { $0.source == .manual && $0.sourceFrameIndex != nil }
            .sorted { $0.code.ordinal < $1.code.ordinal }
    }

    fileprivate mutating func select(_ code: PPointCode) {
        selectedCode = code
        let selection = selection(for: code)
        currentSourceFrameIndex = selection.sourceFrameIndex
            ?? selection.suggestedSourceFrameIndex
            ?? boundedFrame(currentSourceFrameIndex)
        currentSourceFrameIndex = orderedBounds(for: code).clamp(currentSourceFrameIndex)
    }

    fileprivate mutating func step(by amount: Int) {
        let candidate = currentSourceFrameIndex.addingReportingOverflow(amount)
        let value = candidate.overflow
            ? (amount < 0 ? Int.min : Int.max)
            : candidate.partialValue
        currentSourceFrameIndex = orderedBounds(for: selectedCode).clamp(
            boundedFrame(value)
        )
    }

    fileprivate mutating func setSelectedStage() {
        guard let index = selections.firstIndex(where: {
            $0.code == selectedCode
        }), frameCount > 0 else {
            return
        }
        let frame = orderedBounds(for: selectedCode).clamp(
            boundedFrame(currentSourceFrameIndex)
        )
        currentSourceFrameIndex = frame
        selections[index].sourceFrameIndex = frame
        selections[index].source = .manual
    }

    private func orderedBounds(for code: PPointCode) -> ClosedRange<Int> {
        guard frameCount > 0 else { return 0...0 }
        let lower = selections
            .filter { $0.code.ordinal < code.ordinal }
            .compactMap(\.sourceFrameIndex)
            .max()
            .map { min(frameCount - 1, $0 + 1) } ?? 0
        let upper = selections
            .filter { $0.code.ordinal > code.ordinal }
            .compactMap(\.sourceFrameIndex)
            .min()
            .map { max(0, $0 - 1) } ?? (frameCount - 1)
        if lower <= upper {
            return lower...upper
        }
        let fallback = boundedFrame(currentSourceFrameIndex)
        return fallback...fallback
    }

    private func boundedFrame(_ value: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        return min(frameCount - 1, max(0, value))
    }

    private static func validFrame(_ value: Int?, frameCount: Int) -> Int? {
        guard let value, frameCount > 0, (0..<frameCount).contains(value) else {
            return nil
        }
        return value
    }
}

enum PPointCorrectionAction: Equatable {
    case select(PPointCode)
    case step(Int)
    case setSelectedStage
}

enum PPointCorrectionReducer {
    static func reduce(
        state: inout PPointCorrectionState,
        action: PPointCorrectionAction
    ) {
        switch action {
        case let .select(code):
            state.select(code)
        case let .step(amount):
            state.step(by: amount)
        case .setSelectedStage:
            state.setSelectedStage()
        }
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
