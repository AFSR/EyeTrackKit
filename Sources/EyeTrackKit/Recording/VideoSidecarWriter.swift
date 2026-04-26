//
//  VideoSidecarWriter.swift
//
//
//  Writes a CSV file alongside a recorded video, with one row per encoded
//  frame. The first column is the video-relative timestamp in seconds
//  (same clock as the video presentation timestamps), so post-processing
//  tools can align gaze events to frames precisely.
//

import Foundation
import CoreMedia

public final class VideoSidecarWriter {
    public let csvURL: URL

    private let queue = DispatchQueue(label: "dev.ukitomato.EyeTrackKit.sidecar")
    private var fileHandle: FileHandle?
    private var startTime: CMTime?
    private let formatter: NumberFormatter

    public init(videoURL: URL) {
        self.csvURL = videoURL.deletingPathExtension().appendingPathExtension("csv")
        let f = NumberFormatter()
        f.minimumFractionDigits = 6
        f.maximumFractionDigits = 6
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        self.formatter = f
    }

    public func start() throws {
        try queue.sync {
            if FileManager.default.fileExists(atPath: csvURL.path) {
                try FileManager.default.removeItem(at: csvURL)
            }
            FileManager.default.createFile(atPath: csvURL.path, contents: nil)
            self.fileHandle = try FileHandle(forWritingTo: csvURL)
            let header = (["videoTime"] + EyeTrackInfo.csvColumns).joined(separator: ",") + "\n"
            try self.fileHandle?.write(contentsOf: Data(header.utf8))
        }
    }

    public func append(info: EyeTrackInfo, at time: CMTime) {
        queue.async { [weak self] in
            guard let self, let handle = self.fileHandle else { return }
            if self.startTime == nil { self.startTime = time }
            let elapsed = CMTimeSubtract(time, self.startTime ?? .zero).seconds
            let elapsedString = self.formatter.string(from: NSNumber(value: elapsed)) ?? "\(elapsed)"
            var row = [elapsedString]
            row.append(contentsOf: info.toCSV)
            let line = row.joined(separator: ",") + "\n"
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    public func stop() {
        queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
            startTime = nil
        }
    }
}
