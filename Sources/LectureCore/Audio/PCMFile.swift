import Foundation

/// A small streaming WAV writer; an unfinished file remains a .partial artifact.
final class PCMFile {
    let url: URL
    private var handle: FileHandle?
    private(set) var frames: Int64 = 0
    init(url: URL) throws {
        self.url = url
        try Data(repeating: 0, count: 44).write(to: url)
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }
    func append(_ samples: ArraySlice<Float>) throws {
        guard let handle else { throw StorageFailure.invalidData("Audio file is closed.") }
        let pcm: [Int16] = samples.map { Int16((min(1, max(-1, $0))*32767).rounded()).littleEndian }
        try pcm.withUnsafeBytes { try handle.write(contentsOf: $0) }
        frames += Int64(pcm.count)
    }
    func close() throws {
        guard let handle else { return }
        guard frames <= Int64((UInt32.max - 36) / 2) else { throw StorageFailure.invalidData("Recording exceeds WAV size limit.") }
        var header = Data()
        func text(_ value: String) { header.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        text("RIFF"); u32(36 + UInt32(frames)*2); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16); text("data"); u32(UInt32(frames)*2)
        try handle.seek(toOffset: 0); try handle.write(contentsOf: header); try handle.synchronize(); try handle.close()
        self.handle = nil
    }
    deinit { try? handle?.close() }
}
