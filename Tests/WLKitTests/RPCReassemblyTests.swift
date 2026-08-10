import XCTest
@testable import WLKit

/// Reassembly of a reply that spans many reports.
///
/// Measured on the hardware: `fs.read keymap.json` on a pad with custom
/// profiles answers with **11,403 bytes in 187 chunks, all inside 0.39s**. The
/// accumulator was cleared at 8192 characters, which it crossed at 0.29s — so
/// the reply was wiped about 0.1s before its closing brace arrived. The call
/// then timed out, `KeymapManager.apply` threw, the keys were never bound to
/// `KV_OAI_AG*`, and every physical press sent a stock keystroke instead of a
/// `v.oai.hid` report. The pad looked dead while the app looked fine: no error
/// named the cause, and a smaller keymap would have worked.
final class RPCReassemblyTests: XCTestCase {

    /// Frames a payload exactly as the firmware does, and as `call` does on the
    /// way out: `[reportID][channel][len][payload…]`, padded to the report size.
    private func reports(for json: String) -> [[UInt8]] {
        let payload = [UInt8](json.utf8)
        var out: [[UInt8]] = []
        var offset = 0
        while offset < payload.count {
            let n = min(WLDevice.maxChunk, payload.count - offset)
            var report = [UInt8](repeating: 0, count: WLDevice.reportSize)
            report[0] = WLDevice.reportID
            report[1] = WLDevice.channelRPC
            report[2] = UInt8(n)
            report.replaceSubrange(3..<(3 + n), with: payload[offset..<(offset + n)])
            out.append(report)
            offset += n
        }
        return out
    }

    private func keymapReply(id: Int, payloadBytes: Int) -> String {
        let blob = String(repeating: "k", count: payloadBytes)
        return "{\"id\":\(id),\"result\":{\"data\":\"\(blob)\"}}"
    }

    private func deliver(_ json: String, to device: WLDevice) {
        for report in reports(for: json) {
            device.handleReport(report, reportID: UInt32(WLDevice.reportID))
        }
    }

    /// The size the pad actually sends.
    func testAnElevenKilobyteReplyArrivesIntact() {
        let device = WLDevice()
        var received: (id: Int, data: String?)?
        device.onResponse = { id, result, _ in
            received = (id, ((result as? [String: Any])?["data"] as? String))
        }

        deliver(keymapReply(id: 7, payloadBytes: 11_403), to: device)

        XCTAssertEqual(received?.id, 7, "the reply never reassembled")
        XCTAssertEqual(received?.data?.count, 11_403)
    }

    /// Well past anything the firmware sends, so the ceiling is not a new cliff
    /// one keymap edit away.
    ///
    /// Kept at 64 KB rather than higher because reassembly rescans the buffer
    /// for a complete object on every chunk, so this is quadratic in payload
    /// size: 11 KB parses in 0.06s, 256 KB takes 29s. Fine for an 11 KB
    /// keymap, worth knowing before anything asks the pad for a big file.
    func testASixtyFourKilobyteReplyArrivesIntact() {
        let device = WLDevice()
        var length: Int?
        device.onResponse = { _, result, _ in
            length = ((result as? [String: Any])?["data"] as? String)?.count
        }

        deliver(keymapReply(id: 9, payloadBytes: 65_536), to: device)

        XCTAssertEqual(length, 65_536)
    }

    /// The small case that always worked, kept honest.
    func testASingleChunkReplyStillArrives() {
        let device = WLDevice()
        var version: String?
        device.onResponse = { _, result, _ in
            version = (result as? [String: Any])?["version"] as? String
        }

        deliver("{\"id\":1,\"result\":{\"version\":\"v0.6.0\"}}", to: device)

        XCTAssertEqual(version, "v0.6.0")
    }

    /// The guard still has a job: an endless stream that never closes an object
    /// must not be mistaken for a reply, however much of it arrives.
    func testUnterminatedGarbageNeverBecomesAResponse() {
        let device = WLDevice()
        var responses = 0
        device.onResponse = { _, _, _ in responses += 1 }

        for _ in 0..<40 {
            deliver("{\"id\":1,\"result\":{\"data\":\"" + String(repeating: "x", count: 1_000), to: device)
        }

        XCTAssertEqual(responses, 0)
    }
}
