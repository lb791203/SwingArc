import Foundation
import CoreMedia

struct SourceFrameTimeline: Equatable {
    private let presentationTimes: [CMTime]
    private let seconds: [Double]

    init?(presentationTimes rawPresentationTimes: [CMTime]) {
        let ordered = rawPresentationTimes
            .filter {
                $0.isValid
                    && $0.isNumeric
                    && $0.seconds.isFinite
            }
            .sorted { CMTimeCompare($0, $1) < 0 }
        var unique: [CMTime] = []
        for time in ordered where unique.last.map({
            CMTimeCompare($0, time) != 0
        }) ?? true {
            unique.append(time)
        }
        guard !unique.isEmpty else { return nil }
        presentationTimes = unique
        seconds = unique.map(\.seconds)
    }

    init?(duration: Double, constantFrameRate: Double) {
        guard duration.isFinite,
              duration > 0,
              constantFrameRate.isFinite,
              constantFrameRate > 0,
              constantFrameRate == constantFrameRate.rounded(),
              constantFrameRate <= Double(Int32.max) else {
            return nil
        }
        let frameCount = max(1, Int(ceil(duration * constantFrameRate)))
        let timescale = CMTimeScale(constantFrameRate)
        self.init(presentationTimes: (0..<frameCount).map {
            CMTime(value: CMTimeValue($0), timescale: timescale)
        })
    }

    var count: Int {
        presentationTimes.count
    }

    var maximumSourceFrameIndex: Int {
        count - 1
    }

    var averageFrameRate: Double? {
        guard count > 1,
              let first = seconds.first,
              let last = seconds.last,
              last > first else { return nil }
        return Double(count - 1) / (last - first)
    }

    func presentationTime(sourceFrameIndex: Int) -> CMTime? {
        guard presentationTimes.indices.contains(sourceFrameIndex) else {
            return nil
        }
        return presentationTimes[sourceFrameIndex]
    }

    func nearestSourceFrameIndex(at time: Double) -> Int? {
        guard time.isFinite else { return nil }
        let insertion = firstSourceFrameIndex(atOrAfter: time)
        if insertion <= 0 { return 0 }
        if insertion >= count { return maximumSourceFrameIndex }
        let before = insertion - 1
        return abs(seconds[before] - time) < abs(seconds[insertion] - time)
            ? before
            : insertion
    }

    func firstSourceFrameIndex(atOrAfter time: Double) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if seconds[middle] < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    func lastSourceFrameIndex(atOrBefore time: Double) -> Int? {
        let insertion = firstSourceFrameIndex(atOrAfter: time)
        if insertion < count, seconds[insertion] == time {
            return insertion
        }
        let prior = insertion - 1
        return prior >= 0 ? prior : nil
    }

    func matches(
        requestedSourceFrameIndex: Int,
        actualTime: CMTime
    ) -> Bool {
        guard let requested = presentationTime(
            sourceFrameIndex: requestedSourceFrameIndex
        ),
        actualTime.isValid,
        actualTime.isNumeric,
        actualTime.seconds.isFinite,
        nearestSourceFrameIndex(at: actualTime.seconds)
            == requestedSourceFrameIndex else {
            return false
        }
        let requestedSeconds = requested.seconds
        var neighborDistances: [Double] = []
        if requestedSourceFrameIndex > 0 {
            neighborDistances.append(
                requestedSeconds - seconds[requestedSourceFrameIndex - 1]
            )
        }
        if requestedSourceFrameIndex < maximumSourceFrameIndex {
            neighborDistances.append(
                seconds[requestedSourceFrameIndex + 1] - requestedSeconds
            )
        }
        let halfInterval = (neighborDistances.filter { $0 > 0 }.min() ?? 0) / 2
        return abs(actualTime.seconds - requestedSeconds)
            <= max(0.000_001, halfInterval + 0.000_001)
    }
}

enum FrameExtractionTolerancePolicy {
    static func halfFrameSeconds(sourceFrameRate: Double) -> Double? {
        guard sourceFrameRate.isFinite, sourceFrameRate > 0 else { return nil }
        return 0.5 / sourceFrameRate
    }

    static func halfFrameTime(sourceFrameRate: Double) -> CMTime? {
        guard let seconds = halfFrameSeconds(sourceFrameRate: sourceFrameRate) else {
            return nil
        }
        return CMTime(seconds: seconds, preferredTimescale: 60_000)
    }

    /// Integer CFR timelines use their exact source-frame timestamp. For
    /// fractional/VFR metadata, AVAssetImageGenerator can place a nominal
    /// frame time just before its real presentation timestamp and select the
    /// prior frame; asking for the interval center keeps the intended sample
    /// inside the bounded half-frame search window.
    static func decodeRequestTime(
        sourceFrameIndex: Int,
        sourceFrameRate: Double
    ) -> CMTime? {
        guard sourceFrameIndex >= 0,
              sourceFrameRate.isFinite,
              sourceFrameRate > 0 else {
            return nil
        }
        let roundedFrameRate = sourceFrameRate.rounded()
        if sourceFrameRate == roundedFrameRate,
           roundedFrameRate <= Double(Int32.max) {
            return CMTime(
                value: CMTimeValue(sourceFrameIndex),
                timescale: CMTimeScale(roundedFrameRate)
            )
        }
        return CMTime(
            seconds: (Double(sourceFrameIndex) + 0.5) / sourceFrameRate,
            preferredTimescale: 60_000
        )
    }

    static func decodeRequestTime(
        sourceFrameIndex: Int,
        sourceFrameTimeline: SourceFrameTimeline
    ) -> CMTime? {
        sourceFrameTimeline.presentationTime(
            sourceFrameIndex: sourceFrameIndex
        )
    }
}
