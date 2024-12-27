import Foundation
import AVFoundation



protocol AudioChunkDelegate: AnyObject {
  func didReceiveAudioChunk(_ chunk: Data)
}



class CustomMediaRecorder: NSObject, AVAudioRecorderDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  private let audioOutput = AVCaptureAudioDataOutput()
  private var audioData = Data() // Stores raw PCM data
  private var status = CurrentRecordingStatus.NONE

  private var audioSession: AVAudioSession!
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
  private var hasSentWAVHeader = false

  weak var delegate: AudioChunkDelegate?

  private let settings = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 16000,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
  ]

  override init() {
    super.init()
    setupEngine()
    addNotificationObservers()
  }

  deinit {
    NotificationCenter.default.removeObserver(self) // Clean up observers
  }

  fileprivate func setupEngine() {
    do {
      audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.defaultToSpeaker)
      try audioSession.setActive(true)
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
    } catch {
      print("audioSession properties weren't set because of an error.")
    }
    print("[AudioEngine]: Setup finished.")
  }

  func startStreaming() -> Bool {
    do {
      guard (audioEngine.inputNode.inputFormat(forBus: inputBus).channelCount > 0) else {
        print("[AudioEngine]: No input is available.")
        self.streamingData = false
        return false
      }
      try audioEngine.start()
    } catch {
      self.streamingData = false
      print("[AudioEngine]: \(error.localizedDescription)")
      return false
    }
    print("[AudioEngine]: Started tapping microphone.")
    return true
  }

  func stopStreaming() {
    do {
      self.audioEngine.stop()
      self.outputFile = nil
      self.hasSentWAVHeader = false
    } catch {
      print("[AudioEngine]: \(error.localizedDescription)")
    }
  }

  private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    let audioData = bufferToData(buffer: buffer)
    delegate?.didReceiveAudioChunk(audioData)
  }

  private func bufferToData(buffer: AVAudioPCMBuffer) -> Data {
    let audioBuffer = buffer.audioBufferList.pointee.mBuffers
    return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
  }

  public func startRecording() -> Bool {
    hasSentWAVHeader = false
    status = CurrentRecordingStatus.RECORDING
    print("Recording started")
    return startStreaming()
  }

  public func stopRecording() {
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
      status = CurrentRecordingStatus.PAUSED
      return true
    } else {
      return false
    }
  }

  public func resumeRecording() -> Bool {
    if(status == CurrentRecordingStatus.PAUSED) {
      status = CurrentRecordingStatus.RECORDING
      return true
    } else {
      return false
    }
  }

  public func getCurrentStatus() -> CurrentRecordingStatus {
    return status
  }

  private func addNotificationObservers() {
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleInterruption(_:)),
                                           name: AVAudioSession.interruptionNotification,
                                           object: nil)
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
    switch type {
    case .began:
      print("Audio session interruption began.")
      audioEngine.stop()
    case .ended:
      print("Audio session interruption ended.")
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
          resumeAudioSession()
        }
      }
    @unknown default:
      print("Unknown audio session interruption type.")
    }
  }

  private func resumeAudioSession() {
    do {
      try audioSession.setActive(true)
      setupEngine() // Reinitialize and start the audio engine
      print("Audio session resumed and audio engine restarted.")
    } catch {
      print("Failed to reactivate audio session: \(error.localizedDescription)")
    }
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
