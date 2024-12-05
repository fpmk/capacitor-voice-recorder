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

  private var audioEngine: AVAudioEngine = AVAudioEngine()
  private var inputNode: AVAudioInputNode!
  private var audioFormat: AVAudioFormat!

  private var streamingData: Bool = false
  private var numberOfChannels: UInt32 = 1
  private var converterFormat: AVAudioCommonFormat = .pcmFormatInt16
  private var sampleRate: Double = 16000
  private var outputFile: AVAudioFile?
  private let inputBus: AVAudioNodeBus = 0
  private let outputBus: AVAudioNodeBus = 0
  private let bufferSize: AVAudioFrameCount = 4096
  private var inputFormat: AVAudioFormat!


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
    setupEngine()
  }

  fileprivate func setupEngine() {
    /// I don't know what the heck is happening under the hood, but if you don't call these next few lines in one closure your code will crash.
    /// Maybe it's threading issue?
    self.audioEngine.reset()
    let inputNode = audioEngine.inputNode
    inputFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: inputBus, bufferSize: bufferSize, format: inputFormat, block: { [weak self] (buffer, time) in
      if !self!.hasSentWAVHeader {
        let header = self?.createWAVHeader(sampleRate: Int(self!.sampleRate), channels: 1, bitDepth: 16, dataLength: 100 * 1024 * 1024)
        self!.delegate?.didReceiveAudioChunk(header!)
        self!.hasSentWAVHeader = true
      }
      self?.convert(buffer: buffer, time: time.audioTimeStamp.mSampleTime)
    })
    self.audioEngine.prepare()
    print("[AudioEngine]: Setup finished.")
  }

  func startStreaming() {
    guard (audioEngine.inputNode.inputFormat(forBus: inputBus).channelCount > 0) else {
      print("[AudioEngine]: No input is available.")
      self.streamingData = false
      return
    }

    do {
      try audioEngine.start()
    } catch {
      self.streamingData = false
      print("[AudioEngine]: \(error.localizedDescription)")
      return
    }

    print("[AudioEngine]: Started tapping microphone.")
    return
  }

  func stopStreaming() {
    self.audioEngine.stop()
    self.outputFile = nil
    self.audioEngine.reset()
    self.audioEngine.inputNode.removeTap(onBus: inputBus)
    self.hasSentWAVHeader = false
    setupEngine()
  }


  private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    // Convert PCMBuffer to Data
    let audioData = bufferToData(buffer: buffer)
    delegate?.didReceiveAudioChunk(audioData)

  }

  private func bufferToData(buffer: AVAudioPCMBuffer) -> Data {
    let audioBuffer = buffer.audioBufferList.pointee.mBuffers
    return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
  }

  public func startRecording() -> Bool {
    hasSentWAVHeader = false
    startStreaming()
    status = CurrentRecordingStatus.RECORDING
    print("Recording started")
    return true
  }

  public func stopRecording() {
    //    captureSession.stopRunning()
    stopStreaming()
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

  private func convert(buffer: AVAudioPCMBuffer, time: Float64) {
    guard let outputFormat = AVAudioFormat(commonFormat: self.converterFormat, sampleRate: sampleRate, channels: numberOfChannels, interleaved: false) else {
      streamingData = false
      print("[AudioEngine]: Failed to create output format.")
      return
    }

    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      streamingData = false
      print("[AudioEngine]: Failed to create the converter.")
      return
    }

    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = AVAudioConverterInputStatus.haveData
      return buffer
    }

    let targetFrameCapacity = AVAudioFrameCount(outputFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate)
    if let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: targetFrameCapacity) {
      var error: NSError?
      let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

      switch status {
      case .haveData:

        self.processAudioBuffer(convertedBuffer)
        streamingData = true
      case .error:
        streamingData = false
        print("[AudioEngine]: Converter failed, \(error?.localizedDescription ?? "Unknown error")")
      case .endOfStream:
        streamingData = false
        print("[AudioEngine]: The end of stream has been reached. No data was returned.")
      case .inputRanDry:
        streamingData = false
        print("[AudioEngine]: Converter input ran dry.")
      @unknown default:
        streamingData = false
        print("[AudioEngine]: Unknown converter error")
      }

    }

  }
}

private extension FixedWidthInteger {
  var data: Data {
    withUnsafeBytes(of: self.littleEndian) { Data($0) }
  }
}
