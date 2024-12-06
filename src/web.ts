import { PluginListenerHandle, WebPlugin } from '@capacitor/core';

import { VoiceRecorderImpl } from './VoiceRecorderImpl';
import type { CurrentRecordingStatus, GenericResponse, RecordingData, VoiceRecorderPlugin } from './definitions';
import { ListenerCallback } from '@capacitor/core/types/web-plugin';
import AudioRecorder from 'fpmk-simple-audio-recorder';

AudioRecorder.initWorker();

export class VoiceRecorderWeb extends WebPlugin implements VoiceRecorderPlugin {
  private recorder = new AudioRecorder({
    recordingGain: 1, // Initial recording volume
    encoderBitRate: 96, // MP3 encoding bit rate
    streaming: true, // Data will be returned in chunks (ondataavailable callback) as it is encoded,
    streamBufferSize: 4096,
    // rather than at the end as one large blob
    constraints: {
      // Optional audio constraints, see https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia
      channelCount: 1, // Set to 2 to hint for stereo if it's available, or leave as 1 to force mono at all times
      autoGainControl: false,
      echoCancellation: false,
      noiseSuppression: false,
    },
  });
  private voiceRecorderInstance = new VoiceRecorderImpl(this.recorder, this);

  public canDeviceVoiceRecord(): Promise<GenericResponse> {
    return VoiceRecorderImpl.canDeviceVoiceRecord();
  }

  public hasAudioRecordingPermission(): Promise<GenericResponse> {
    return VoiceRecorderImpl.hasAudioRecordingPermission();
  }

  public requestAudioRecordingPermission(): Promise<GenericResponse> {
    return VoiceRecorderImpl.requestAudioRecordingPermission();
  }

  public startRecording(): Promise<GenericResponse> {
    return this.voiceRecorderInstance.startRecording();
  }

  public stopRecording(): Promise<RecordingData> {
    return this.voiceRecorderInstance.stopRecording();
  }

  public pauseRecording(): Promise<GenericResponse> {
    return this.voiceRecorderInstance.pauseRecording();
  }

  public resumeRecording(): Promise<GenericResponse> {
    return this.voiceRecorderInstance.resumeRecording();
  }

  public getCurrentStatus(): Promise<CurrentRecordingStatus> {
    return this.voiceRecorderInstance.getCurrentStatus();
  }

  addListener(eventName: string, listenerFunc: ListenerCallback): Promise<PluginListenerHandle> {
    return super.addListener(eventName, listenerFunc);
  }
}
