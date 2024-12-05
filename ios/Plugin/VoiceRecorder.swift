import Foundation
import AVFoundation
import Capacitor

@objc(VoiceRecorder)
public class VoiceRecorder: CAPPlugin, AudioChunkDelegate {

  private var customMediaRecorder: CustomMediaRecorder? = nil

  override init() {
    super.init()
    customMediaRecorder = CustomMediaRecorder()
    customMediaRecorder?.delegate = self
  }

  @objc func canDeviceVoiceRecord(_ call: CAPPluginCall) {
    call.resolve(ResponseGenerator.successResponse())
  }

  @objc func requestAudioRecordingPermission(_ call: CAPPluginCall) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      if granted {
        call.resolve(ResponseGenerator.successResponse())
      } else {
        call.resolve(ResponseGenerator.failResponse())
      }
    }
  }

  @objc func hasAudioRecordingPermission(_ call: CAPPluginCall) {
    call.resolve(ResponseGenerator.fromBoolean(doesUserGaveAudioRecordingPermission()))
  }


  @objc func startRecording(_ call: CAPPluginCall) {
    if(!doesUserGaveAudioRecordingPermission()) {
      call.reject(Messages.MISSING_PERMISSION)
      return
    }

    //        if(customMediaRecorder != nil) {
    //            call.reject(Messages.ALREADY_RECORDING)
    //            return
    //        }

    if(customMediaRecorder == nil) {
      call.reject(Messages.CANNOT_RECORD_ON_THIS_PHONE)
      return
    }

    let successfullyStartedRecording = customMediaRecorder!.startRecording()
    if successfullyStartedRecording == false {
      //            customMediaRecorder = nil
      call.reject(Messages.CANNOT_RECORD_ON_THIS_PHONE)
    } else {
      call.resolve(ResponseGenerator.successResponse())
    }
  }

  @objc func stopRecording(_ call: CAPPluginCall) {
    if(customMediaRecorder == nil) {
      call.reject(Messages.RECORDING_HAS_NOT_STARTED)
      return
    }

    customMediaRecorder?.stopRecording()
    //            customMediaRecorder = nil
    call.resolve(ResponseGenerator.successResponse())
  }

  @objc func getCurrentStatus(_ call: CAPPluginCall) {
    if(customMediaRecorder == nil) {
      call.resolve(ResponseGenerator.statusResponse(CurrentRecordingStatus.NONE))
    } else {
      call.resolve(ResponseGenerator.statusResponse(customMediaRecorder?.getCurrentStatus() ?? CurrentRecordingStatus.NONE))
    }
  }

  // Delegate method to handle audio chunks
  func didReceiveAudioChunk(_ chunk: Data) {
    let base64Chunk = chunk.base64EncodedString()
    var jsonObject: JSObject = [:] // Initialize an empty JSObject
    jsonObject["data"] = base64Chunk // Add the "data" key with the Base64 string value
    notifyListeners("onAudioChunk", data: jsonObject)
  }

  func doesUserGaveAudioRecordingPermission() -> Bool {
    return AVAudioSession.sharedInstance().recordPermission == AVAudioSession.RecordPermission.granted
  }
}
