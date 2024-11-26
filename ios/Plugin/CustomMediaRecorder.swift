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
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    private var audioBuffer = Data()
    private let chunkSize: Int = 1024 * 4 // Example: 4 KB per chunk

    private func getDirectoryToSaveAudioFile() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
    
    public func startRecording() -> Bool {
        do {
            recordingSession = AVAudioSession.sharedInstance()
            originalRecordingSessionCategory = recordingSession.category
            try recordingSession.setCategory(AVAudioSession.Category.playAndRecord)
            try recordingSession.setActive(true)
            audioFilePath = getDirectoryToSaveAudioFile().appendingPathComponent("\(UUID().uuidString).aac")
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
