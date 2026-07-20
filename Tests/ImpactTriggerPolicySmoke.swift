import Foundation

@main
struct ImpactTriggerPolicySmoke {
    static func main() {
        var policy = ImpactTriggerPolicy()
        for frame in 0..<8 {
            precondition(!policy.ingest(rms: 0.005, at: Double(frame) * 0.02))
        }
        precondition(!policy.ingest(rms: 0.015, at: 0.20))
        precondition(policy.ingest(rms: 0.045, at: 0.22))
        precondition(!policy.ingest(rms: 0.08, at: 0.30))
        precondition(policy.ingest(rms: 0.05, at: 1.10))

        var quietPolicy = ImpactTriggerPolicy()
        for frame in 0..<8 {
            precondition(!quietPolicy.ingest(rms: 0.0005, at: Double(frame) * 0.02))
        }
        precondition(!quietPolicy.ingest(rms: 0.020, at: 0.20))
        precondition(quietPolicy.ingest(rms: 0.030, at: 0.22))
    }
}
