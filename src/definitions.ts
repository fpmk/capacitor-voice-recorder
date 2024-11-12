import { PluginListenerHandle } from '@capacitor/core';
import { ListenerCallback } from '@capacitor/core/types/web-plugin';

export type Base64String = string;

export interface RecordingData {
  value: {
    recordDataBase64: Base64String;
    msDuration: number;
    mimeType: string;
  };
}

export interface GenericResponse {
  value: boolean;
}

export const RecordingStatus = {
  RECORDING: 'RECORDING',
  PAUSED: 'PAUSED',
  NONE: 'NONE',
} as const;

export interface CurrentRecordingStatus {
  status: (typeof RecordingStatus)[keyof typeof RecordingStatus];
}

export interface AudioChunkEvent {
  data: string; // Base64 encoded audio chunk data
}

export interface VoiceRecorderPlugin {
  canDeviceVoiceRecord(): Promise<GenericResponse>;

  requestAudioRecordingPermission(): Promise<GenericResponse>;

  hasAudioRecordingPermission(): Promise<GenericResponse>;

  startRecording(): Promise<GenericResponse>;

  stopRecording(): Promise<RecordingData>;

  pauseRecording(): Promise<GenericResponse>;

  resumeRecording(): Promise<GenericResponse>;

  getCurrentStatus(): Promise<CurrentRecordingStatus>;

  addListener(
    eventName: string, listenerFunc: ListenerCallback
  ): Promise<PluginListenerHandle>;
}
