import XCTest
@testable import EyeTrackKit

final class EyeTrackKitTests: XCTestCase {

    // MARK: - AffineTransform2D

    func testAffineFitRecoversTranslation() {
        let translation = CGPoint(x: 100, y: 50)
        let raw = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 100),
            CGPoint(x: 100, y: 100),
        ]
        let samples = raw.map { (raw: $0,
                                target: CGPoint(x: $0.x + translation.x,
                                                y: $0.y + translation.y)) }
        guard let result = AffineTransform2D.fit(from: samples) else {
            XCTFail("fit returned nil"); return
        }
        let mapped = result.transform.apply(to: CGPoint(x: 25, y: 75))
        XCTAssertEqual(mapped.x, 125, accuracy: 1e-6)
        XCTAssertEqual(mapped.y, 125, accuracy: 1e-6)
        XCTAssertLessThan(result.residuals.max() ?? 999, 1e-6)
    }

    func testAffineFitRecoversScaleAndTranslation() {
        // Target = 2*raw + 10
        let samples: [(raw: CGPoint, target: CGPoint)] = [
            (CGPoint(x: 0, y: 0),   CGPoint(x: 10, y: 10)),
            (CGPoint(x: 50, y: 0),  CGPoint(x: 110, y: 10)),
            (CGPoint(x: 0, y: 50),  CGPoint(x: 10, y: 110)),
            (CGPoint(x: 50, y: 50), CGPoint(x: 110, y: 110)),
        ]
        let result = AffineTransform2D.fit(from: samples)!
        let m = result.transform.apply(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(m.x, 210, accuracy: 1e-3)
        XCTAssertEqual(m.y, 210, accuracy: 1e-3)
    }

    func testAffineFitRejectsCollinearInput() {
        let samples: [(raw: CGPoint, target: CGPoint)] = [
            (CGPoint(x: 0, y: 0),  CGPoint(x: 0, y: 0)),
            (CGPoint(x: 1, y: 1),  CGPoint(x: 2, y: 2)),
            (CGPoint(x: 2, y: 2),  CGPoint(x: 4, y: 4)),
        ]
        XCTAssertNil(AffineTransform2D.fit(from: samples))
    }

    // MARK: - CalibrationProfile JSON round-trip

    func testCalibrationProfileRoundTrip() throws {
        let profile = CalibrationProfile(
            deviceTypeRaw: DeviceType.iPhone15Pro.rawValue,
            screenPointSize: CGSize(width: 393, height: 852),
            targets: [CalibrationTarget(point: CGPoint(x: 100, y: 100))],
            samples: [],
            transform: .identity,
            residuals: [1.0, 2.0, 3.0]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationProfile.self, from: data)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.deviceTypeRaw, profile.deviceTypeRaw)
        XCTAssertEqual(decoded.screenPointSize, profile.screenPointSize)
        XCTAssertEqual(decoded.transform, profile.transform)
    }

    // MARK: - RingBuffer

    func testRingBufferEvictsOldestWhenFull() {
        var buf = RingBuffer<Int>(capacity: 3)
        XCTAssertNil(buf.append(1))
        XCTAssertNil(buf.append(2))
        XCTAssertNil(buf.append(3))
        XCTAssertEqual(buf.append(4), 1) // evicts 1
        XCTAssertEqual(buf.append(5), 2) // evicts 2
        XCTAssertEqual(buf.count, 3)
    }

    // MARK: - KalmanFilter

    func testKalmanFilterConvergesToConstant() {
        var f = KalmanFilter1D(processNoise: 1e-3, measurementNoise: 1e-1)
        // Feed noisy measurements around 100
        let target: Double = 100
        var last: Double = 0
        for _ in 0..<100 {
            let noisy = target + Double.random(in: -2...2)
            last = f.update(noisy)
        }
        XCTAssertEqual(last, target, accuracy: 1.0)
    }

    // MARK: - FixationDetector

    func testFixationDetectorReportsStablePoint() {
        var detector = FixationDetector(configuration:
            FixationDetector.Configuration(dispersionThreshold: 5,
                                           minimumFixationDuration: 0.05))
        var events: [TrackingEvent] = []
        let start = Date()
        for i in 0..<10 {
            let t = start.addingTimeInterval(Double(i) * 0.02)
            events.append(contentsOf: detector.ingest(
                point: CGPoint(x: 100, y: 100),
                time: t, confidence: 1
            ))
        }
        // Move far away → should close the fixation
        events.append(contentsOf: detector.ingest(
            point: CGPoint(x: 500, y: 500),
            time: start.addingTimeInterval(0.3), confidence: 1
        ))
        let fixations = events.compactMap { ev -> CGPoint? in
            if case .fixation(let p, _, _) = ev { return p }
            return nil
        }
        XCTAssertEqual(fixations.count, 1)
        XCTAssertEqual(fixations.first?.x ?? 0, 100, accuracy: 1)
        XCTAssertEqual(fixations.first?.y ?? 0, 100, accuracy: 1)
    }
}
