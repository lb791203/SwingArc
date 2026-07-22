import Foundation

struct LiveSwingTriggerDetector {
    let configuration: LiveSwingTriggerConfiguration

    private(set) var state: LiveSwingTriggerState = .searchingForPerson
    private(set) var emittedBoundaryCount = 0

    private var lastTime: TimeInterval?
    private var visibleSince: TimeInterval?
    private var onsetConfirmationCount = 0
    private var onsetFirstTime: TimeInterval?
    private var swingStartTime: TimeInterval?
    private var settledSince: TimeInterval?
    private var cooldownSince: TimeInterval?

    init(configuration: LiveSwingTriggerConfiguration = .standard) {
        self.configuration = configuration
    }

    mutating func reset() {
        state = .searchingForPerson
        emittedBoundaryCount = 0
        resetTransientState()
        lastTime = nil
    }

    mutating func ingest(_ sample: LivePoseMotionSample) -> LiveSwingTriggerUpdate {
        guard sample.time.isFinite else {
            resetForInvalidTimeline()
            return update()
        }
        if let lastTime, sample.time < lastTime {
            resetForInvalidTimeline()
        }
        lastTime = sample.time

        switch state {
        case .searchingForPerson:
            ingestSearching(sample)
        case .ready:
            ingestReady(sample)
        case .swingInProgress:
            if let boundary = ingestSwing(sample) {
                return update(boundary: boundary)
            }
        case .finishing:
            if let boundary = ingestFinishing(sample) {
                return update(boundary: boundary)
            }
        case .cooldown:
            ingestCooldown(sample)
        }

        return update()
    }

    private mutating func ingestSearching(_ sample: LivePoseMotionSample) {
        guard sample.personVisible else {
            visibleSince = nil
            return
        }
        if visibleSince == nil {
            visibleSince = sample.time
        }
        if sample.time - (visibleSince ?? sample.time) >= configuration.personStableDuration {
            state = .ready
            onsetConfirmationCount = 0
            onsetFirstTime = nil
        }
    }

    private mutating func ingestReady(_ sample: LivePoseMotionSample) {
        guard sample.personVisible else {
            state = .searchingForPerson
            visibleSince = nil
            onsetConfirmationCount = 0
            onsetFirstTime = nil
            return
        }

        let coordinatedOnset = sample.normalizedWristSpeed >= configuration.wristOnsetSpeed &&
            sample.normalizedTorsoSpeed >= configuration.torsoCoordinationSpeed &&
            sample.backswingDirectionScore >= 0.5
        guard coordinatedOnset else {
            onsetConfirmationCount = 0
            onsetFirstTime = nil
            return
        }

        if onsetConfirmationCount == 0 {
            onsetFirstTime = sample.time
        }
        onsetConfirmationCount += 1
        if onsetConfirmationCount >= configuration.onsetConfirmationSamples {
            swingStartTime = onsetFirstTime ?? sample.time
            settledSince = nil
            state = .swingInProgress
        }
    }

    private mutating func ingestSwing(
        _ sample: LivePoseMotionSample
    ) -> PracticeCaptureBoundary? {
        guard let swingStartTime else {
            resetForInvalidTimeline()
            return nil
        }
        if sample.time - swingStartTime >= configuration.maximumSwingDuration {
            return finish(at: sample.time, quality: .possibleIncomplete)
        }
        if sample.personVisible, sample.followThroughScore >= 0.5 {
            state = .finishing
            updateSettledStart(with: sample)
        }
        return nil
    }

    private mutating func ingestFinishing(
        _ sample: LivePoseMotionSample
    ) -> PracticeCaptureBoundary? {
        guard let swingStartTime else {
            resetForInvalidTimeline()
            return nil
        }
        if sample.time - swingStartTime >= configuration.maximumSwingDuration {
            return finish(at: sample.time, quality: .possibleIncomplete)
        }
        guard sample.personVisible else {
            settledSince = nil
            return nil
        }

        updateSettledStart(with: sample)
        guard let settledSince,
              sample.time - swingStartTime >= configuration.minimumSwingDuration,
              sample.time - settledSince >= configuration.finishSettledDuration else {
            return nil
        }
        return finish(at: sample.time, quality: .complete)
    }

    private mutating func updateSettledStart(with sample: LivePoseMotionSample) {
        let isSettled = sample.normalizedWristSpeed <= configuration.settledSpeed &&
            sample.normalizedTorsoSpeed <= configuration.settledSpeed
        if isSettled {
            settledSince = settledSince ?? sample.time
        } else {
            settledSince = nil
        }
    }

    private mutating func ingestCooldown(_ sample: LivePoseMotionSample) {
        guard let cooldownSince,
              sample.time - cooldownSince >= configuration.cooldownDuration else {
            return
        }
        onsetConfirmationCount = 0
        onsetFirstTime = nil
        swingStartTime = nil
        settledSince = nil
        if sample.personVisible {
            visibleSince = sample.time - configuration.personStableDuration
            state = .ready
        } else {
            visibleSince = nil
            state = .searchingForPerson
        }
    }

    private mutating func finish(
        at time: TimeInterval,
        quality: PracticeCaptureQuality
    ) -> PracticeCaptureBoundary? {
        guard let swingStartTime else { return nil }
        let boundary = PracticeCaptureBoundary(
            swingStartTime: swingStartTime,
            swingEndTime: max(swingStartTime, time),
            quality: quality
        )
        emittedBoundaryCount += 1
        cooldownSince = time
        state = .cooldown
        return boundary
    }

    private mutating func resetForInvalidTimeline() {
        state = .searchingForPerson
        resetTransientState()
        lastTime = nil
    }

    private mutating func resetTransientState() {
        visibleSince = nil
        onsetConfirmationCount = 0
        onsetFirstTime = nil
        swingStartTime = nil
        settledSince = nil
        cooldownSince = nil
    }

    private func update(
        boundary: PracticeCaptureBoundary? = nil
    ) -> LiveSwingTriggerUpdate {
        LiveSwingTriggerUpdate(state: state, boundary: boundary)
    }
}
