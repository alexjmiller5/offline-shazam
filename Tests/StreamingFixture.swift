import AVFoundation
import ShazamKit
import XCTest

func streamingFixture(seconds: Int = 10, seed: UInt32 = 12345) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44100 * seconds)))
    buffer.frameLength = buffer.frameCapacity
    let samples = try XCTUnwrap(buffer.floatChannelData?[0])
    var seed = seed
    for index in 0..<Int(buffer.frameLength) {
        seed = 1664525 &* seed &+ 1013904223
        samples[index] = (Float(seed) / Float(UInt32.max) - 0.5) * 0.7
    }
    return buffer
}

func unrelatedStreamingSession() throws -> SHSession {
    let generator = SHSignatureGenerator()
    try generator.append(streamingFixture(seed: 54321), at: nil)
    let catalog = SHCustomCatalog()
    try catalog.addReferenceSignature(generator.signature(), representing: [SHMediaItem(properties: [.title: "Other Song", .artist: "Example Artist"])])
    return SHSession(catalog: catalog)
}
