import Foundation

/// Download speed over the last few seconds, shown beside every download's progress.
public struct DownloadRate: Sendable {
    private var samples: [(time: TimeInterval, bytes: Int64)] = []

    public init() {}

    /// Bytes per second, once a second of samples is in.
    public mutating func add(_ bytes: Int64, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        // Fewer bytes than before: the download started over.
        if let last = samples.last, bytes < last.bytes { samples.removeAll() }
        samples.append((time, bytes))
        // The last five seconds, but always two samples, so sparse reports still give a rate.
        while samples.count > 2, time - samples[0].time > 5 { samples.removeFirst() }
        guard let first = samples.first, time - first.time >= 1 else { return nil }
        return Double(bytes - first.bytes) / (time - first.time)
    }

    /// "31.7 MB / 79.1 MB · 2.4 MB/s"
    public static func amount(received: Int64, total: Int64?, speed: Double?) -> String {
        var text = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        if let total { text += " / " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file) }
        if let speed { text += " · " + ByteCountFormatter.string(fromByteCount: Int64(max(speed, 0)), countStyle: .file) + "/s" }
        return text
    }
}
