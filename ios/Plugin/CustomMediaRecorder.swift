import Foundation
import AVFoundation

protocol AudioChunkDelegate: AnyObject {
    func didReceiveAudioChunk(_ chunk: Data)
}

class CustomMediaRecorder: NSObject, AVAudioRecorderDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    private let captureSession = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var audioData = Data() // Stores raw PCM data
    private var status = CurrentRecordingStatus.NONE

    weak var delegate: AudioChunkDelegate?

    private let settings = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]
    private var hasSentWAVHeader = false

    override init() {
        super.init()
        setupCaptureSession()
    }

   private func setupCaptureSession() {
       captureSession.beginConfiguration()

       // Add audio input
       guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
           print("No audio device available")
           return
       }

       do {
           let audioInput = try AVCaptureDeviceInput(device: audioDevice)
           if captureSession.canAddInput(audioInput) {
               captureSession.addInput(audioInput)
           } else {
               print("Cannot add audio input")
               return
           }
       } catch {
           print("Failed to create audio input: \(error.localizedDescription)")
           return
       }

       // Add audio output
       if captureSession.canAddOutput(audioOutput) {
           captureSession.addOutput(audioOutput)
           audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "AudioQueue"))
       } else {
           print("Cannot add audio output")
           return
       }

       captureSession.commitConfiguration()
   }

   func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
       guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
           print("Failed to get audio buffer")
           return
       }

       let length = CMBlockBufferGetDataLength(blockBuffer)
       var rawData = Data(count: length)
       rawData.withUnsafeMutableBytes { bytes in
           CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes)
       }
        delegate?.didReceiveAudioChunk(rawData)
   }

    public func startRecording() -> Bool {
        if !hasSentWAVHeader {
            let header = createWAVHeader(16000, 1, 16, 44)
            delegate?.didReceiveAudioChunk(header)
            hasSentWAVHeader = true
        }
        audioData = Data() // Reset audio data
        captureSession.startRunning()
        status = CurrentRecordingStatus.RECORDING
        print("Recording started")
        return true
    }

    public func stopRecording() {
        captureSession.stopRunning()
        print("Recording stopped and saved as WAV")
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

    public func pauseRecording() -> Bool {
        if(status == CurrentRecordingStatus.RECORDING) {
            captureSession.stopRunning()
            status = CurrentRecordingStatus.PAUSED
            return true
        } else {
            return false
        }
    }

    public func resumeRecording() -> Bool {
        if(status == CurrentRecordingStatus.PAUSED) {
            captureSession.startRunning()
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
