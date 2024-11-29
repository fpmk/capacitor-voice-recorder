import Foundation
import AVFoundation

protocol AudioChunkDelegate: AnyObject {
    func didReceiveAudioChunk(_ chunk: Data)
}

class CustomMediaRecorder: NSObject, AVAudioRecorderDelegate {

    private var recordingSession: AVAudioSession!
    private var audioRecorder: AVAudioRecorder!
    private var audioFilePath: URL!
    private var originalRecordingSessionCategory: AVAudioSession.Category!
    private var status = CurrentRecordingStatus.NONE

    weak var delegate: AudioChunkDelegate?

    private let settings = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    private var audioBuffer = Data()
    private let chunkSize: Int = 1024 * 4 // Example: 4 KB per chunk
    private var hasSentWAVHeader = false

    private func getDirectoryToSaveAudioFile() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    public func startRecording() -> Bool {
        do {
            recordingSession = AVAudioSession.sharedInstance()
            originalRecordingSessionCategory = recordingSession.category
            try recordingSession.setCategory(AVAudioSession.Category.playAndRecord)
            try recordingSession.setActive(true)
            audioFilePath = getDirectoryToSaveAudioFile().appendingPathComponent("\(UUID().uuidString).wav")
            audioRecorder = try AVAudioRecorder(url: audioFilePath, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            audioRecorder.record(forDuration: 0) // Record indefinitely

            status = CurrentRecordingStatus.RECORDING

            // Monitor the audio file for changes
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.monitorAudioFile()
            }

            return true
        } catch {
            return false
        }
    }

    public func stopRecording() {
        do {
            audioRecorder.stop()
            try recordingSession.setActive(false)
            try recordingSession.setCategory(originalRecordingSessionCategory)
            originalRecordingSessionCategory = nil
            audioRecorder = nil
            recordingSession = nil
            status = CurrentRecordingStatus.NONE
            try FileManager.default.removeItem(at: audioFilePath)
        } catch {}
    }

    private func monitorAudioFile() {
        while audioRecorder.isRecording {
            guard let recorder = audioRecorder else { return }
            recorder.updateMeters()

            do {
                // Read raw data from the file
                let audioData = try Data(contentsOf: audioFilePath)

                // Append to the buffer
                audioBuffer.append(audioData)

                // Check if the WAV header has been sent
                if !hasSentWAVHeader {
                    let header = createWAVHeader(sampleRate: 16000, channels: 1, bitDepth: 16, dataLength: 0xFFFFFFFF)
                    delegate?.didReceiveAudioChunk(header)
                    hasSentWAVHeader = true
                }

                // Check if the buffer has reached the desired chunk size
                if audioBuffer.count >= chunkSize {
                    let chunk = audioBuffer.prefix(chunkSize) // Extract the chunk
                    audioBuffer.removeFirst(chunkSize)        // Remove the chunk from the buffer
                    delegate?.didReceiveAudioChunk(chunk)     // Notify the delegate
                }
            } catch {
                print("Error monitoring audio file: \(error)")
            }

            // Sleep briefly to avoid overloading the CPU
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Flush remaining data in the buffer
        if !audioBuffer.isEmpty {
            delegate?.didReceiveAudioChunk(audioBuffer)
            audioBuffer.removeAll()
        }
    }

    private func createWAVHeader(sampleRate: Int, channels: Int, bitDepth: Int, dataLength: Int) -> Data {
        let chunkSize = 36 + dataLength
        let subChunk1Size = 16
        let audioFormat = 1 // PCM
        let byteRate = sampleRate * channels * (bitDepth / 8)
        let blockAlign = channels * (bitDepth / 8)

        var header = Data()

        header.append("RIFF".data(using: .ascii)!) // ChunkID
        header.append(UInt32(chunkSize).littleEndian.data) // ChunkSize
        header.append("WAVE".data(using: .ascii)!) // Format
        header.append("fmt ".data(using: .ascii)!) // Subchunk1ID
        header.append(UInt32(subChunk1Size).littleEndian.data) // Subchunk1Size
        header.append(UInt16(audioFormat).littleEndian.data) // AudioFormat
        header.append(UInt16(channels).littleEndian.data) // NumChannels
        header.append(UInt32(sampleRate).littleEndian.data) // SampleRate
        header.append(UInt32(byteRate).littleEndian.data) // ByteRate
        header.append(UInt16(blockAlign).littleEndian.data) // BlockAlign
        header.append(UInt16(bitDepth).littleEndian.data) // BitsPerSample
        header.append("data".data(using: .ascii)!) // Subchunk2ID
        header.append(UInt32(dataLength).littleEndian.data) // Subchunk2Size

        return header
    }

    public func getOutputFile() -> URL {
        return audioFilePath
    }

    public func pauseRecording() -> Bool {
        if(status == CurrentRecordingStatus.RECORDING) {
            audioRecorder.pause()
            status = CurrentRecordingStatus.PAUSED
            return true
        } else {
            return false
        }
    }

    public func resumeRecording() -> Bool {
        if(status == CurrentRecordingStatus.PAUSED) {
            audioRecorder.record()
            status = CurrentRecordingStatus.RECORDING
            return true
        } else {
            return false
        }
    }

    public func getCurrentStatus() -> CurrentRecordingStatus {
        return status
    }
}

private extension FixedWidthInteger {
    var data: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
