import { PluginListenerHandle, WebPlugin } from '@capacitor/core';

import { VoiceRecorderImpl } from './VoiceRecorderImpl';
import type { CurrentRecordingStatus, GenericResponse, RecordingData, VoiceRecorderPlugin } from './definitions';
import { ListenerCallback } from '@capacitor/core/types/web-plugin';

export class VoiceRecorderWeb extends WebPlugin implements VoiceRecorderPlugin {
  private voiceRecorderInstance = new VoiceRecorderImpl();

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
    return this.voiceRecorderInstance.startRecording(this);
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

  addListener(
    eventName: string, listenerFunc: ListenerCallback
  ): Promise<PluginListenerHandle> {
    return super.addListener(eventName, listenerFunc);
  }
}
