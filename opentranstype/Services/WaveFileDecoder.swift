import Foundation

func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)

    guard data.count > 12,
          String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: data[8..<12], encoding: .ascii) == "WAVE" else {
        throw WaveFileError.invalidFormat
    }

    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(bytes: data[offset..<offset + 4], encoding: .ascii) ?? ""
        let chunkSize = data[(offset + 4)..<(offset + 8)].withUnsafeBytes {
            Int($0.loadUnaligned(as: UInt32.self).littleEndian)
        }

        offset += 8

        if chunkID == "data" {
            return stride(from: offset, to: min(offset + chunkSize, data.count), by: 2).map {
                data[$0..<$0 + 2].withUnsafeBytes {
                    let sample = Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
                    return max(-1.0, min(Float(sample) / 32767.0, 1.0))
                }
            }
        }

        offset += chunkSize
        if chunkSize % 2 != 0 {
            offset += 1
        }
    }

    throw WaveFileError.dataChunkNotFound
}

enum WaveFileError: Error {
    case invalidFormat
    case dataChunkNotFound
}
