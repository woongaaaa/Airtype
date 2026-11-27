import Foundation

public struct OneEuroFilter: Sendable {
    private var value: Double?
    private var derivative = 0.0
    private var time: Double?
    public var minCutoff: Double = 1.5
    public var beta: Double = 4
    public init() {}
    public mutating func update(_ raw: Double, at now: Double) -> Double {
        guard let previous = value, let last = time, now > last, now-last < 0.3 else {
            value = raw; time = now; derivative = 0; return raw
        }
        let dt = now-last
        func alpha(_ cutoff: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }
        derivative += alpha(1) * ((raw-previous)/dt - derivative)
        let result = previous + alpha(minCutoff + beta * abs(derivative)) * (raw-previous)
        value = result; time = now; return result
    }
    public mutating func reset() { self = OneEuroFilter() }
}
