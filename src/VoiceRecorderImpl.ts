import getBlobDuration from 'get-blob-duration';

import type {
  AudioChunkEvent,
  Base64String,
  CurrentRecordingStatus,
  GenericResponse,
  RecordingData,
} from './definitions';
import { RecordingStatus } from './definitions';
import {
  alreadyRecordingError,
  couldNotQueryPermissionStatusError,
  deviceCannotVoiceRecordError,
  emptyRecordingError,
  failedToFetchRecordingError,
  failedToRecordError,
  failureResponse,
  missingPermissionError,
  recordingHasNotStartedError,
  successResponse,
} from './predefined-web-responses';

// these mime types will be checked one by one in order until one of them is found to be supported by the current browser
const possibleMimeTypes = ['audio/aac', 'audio/webm;codecs=opus', 'audio/mp4', 'audio/webm', 'audio/ogg;codecs=opus'];
const neverResolvingPromise = (): Promise<any> => new Promise(() => undefined);

export class VoiceRecorderImpl {
  private mediaRecorder: MediaRecorder | null = null;
  private chunks: any[] = [];
  private pendingResult: Promise<RecordingData> = neverResolvingPromise();
  private buffer: Blob[] = [];
  private firstChunk = false;
  private bufferSize = 0;
  private chunkSize = 4096; // 4KB in bytes
  private firstChunkSize = 158; // 44 bytes

  public static async canDeviceVoiceRecord(): Promise<GenericResponse> {
    if (navigator?.mediaDevices?.getUserMedia == null || VoiceRecorderImpl.getSupportedMimeType() == null) {
      return failureResponse();
    } else {
      return successResponse();
    }
  }

  public async startRecording(_this: any): Promise<GenericResponse> {
    if (this.mediaRecorder != null) {
      throw alreadyRecordingError();
    }
    const deviceCanRecord = await VoiceRecorderImpl.canDeviceVoiceRecord();
    if (!deviceCanRecord.value) {
      throw deviceCannotVoiceRecordError();
    }
    const havingPermission = await VoiceRecorderImpl.hasAudioRecordingPermission().catch(() => successResponse());
    if (!havingPermission.value) {
      throw missingPermissionError();
    }
    return navigator.mediaDevices
      .getUserMedia({ audio: true })
      .then((res) => this.onSuccessfullyStartedRecording(res, _this))
      .catch(this.onFailedToStartRecording.bind(this));
  }

  public async stopRecording(): Promise<RecordingData> {
    if (this.mediaRecorder == null) {
      throw recordingHasNotStartedError();
    }
    try {
      this.mediaRecorder.stop();
      this.mediaRecorder.stream.getTracks().forEach((track) => track.stop());
      this.mediaRecorder = null;
      return this.pendingResult;
    } catch (ignore) {
      this.prepareInstanceForNextOperation();
      throw failedToFetchRecordingError();
    } finally {
      // this.prepareInstanceForNextOperation();
    }
  }

  public static async hasAudioRecordingPermission(): Promise<GenericResponse> {
    if (navigator.permissions.query == null) {
      if (navigator.mediaDevices == null) {
        return Promise.reject(couldNotQueryPermissionStatusError());
      }
      return navigator.mediaDevices
        .getUserMedia({ audio: true })
        .then(() => successResponse())
        .catch(() => {
          throw couldNotQueryPermissionStatusError();
        });
    }

    return navigator.permissions
      .query({ name: 'microphone' as any })
      .then((result) => ({ value: result.state === 'granted' }))
      .catch(() => {
        throw couldNotQueryPermissionStatusError();
      });
  }

  public static async requestAudioRecordingPermission(): Promise<GenericResponse> {
    const havingPermission = await VoiceRecorderImpl.hasAudioRecordingPermission().catch(() => failureResponse());
    if (havingPermission.value) {
      return successResponse();
    }

    return navigator.mediaDevices
      .getUserMedia({ audio: true })
      .then(() => successResponse())
      .catch(() => failureResponse());
  }

  public pauseRecording(): Promise<GenericResponse> {
    if (this.mediaRecorder == null) {
      throw recordingHasNotStartedError();
    } else if (this.mediaRecorder.state === 'recording') {
      this.mediaRecorder.pause();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public resumeRecording(): Promise<GenericResponse> {
    if (this.mediaRecorder == null) {
      throw recordingHasNotStartedError();
    } else if (this.mediaRecorder.state === 'paused') {
      this.mediaRecorder.resume();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public getCurrentStatus(): Promise<CurrentRecordingStatus> {
    if (this.mediaRecorder == null) {
      return Promise.resolve({ status: RecordingStatus.NONE });
    } else if (this.mediaRecorder.state === 'recording') {
      return Promise.resolve({ status: RecordingStatus.RECORDING });
    } else if (this.mediaRecorder.state === 'paused') {
      return Promise.resolve({ status: RecordingStatus.PAUSED });
    } else {
      return Promise.resolve({ status: RecordingStatus.NONE });
    }
  }

  public static getSupportedMimeType(): string | null {
    if (MediaRecorder?.isTypeSupported == null) return null;
    const foundSupportedType = possibleMimeTypes.find((type) => MediaRecorder.isTypeSupported(type));
    return foundSupportedType ?? null;
  }

  private onSuccessfullyStartedRecording(stream: MediaStream, _this: any): GenericResponse {
    this.firstChunk = false;
    this.pendingResult = new Promise((resolve, reject) => {
      this.mediaRecorder = new MediaRecorder(stream);
      this.mediaRecorder.onerror = () => {
        this.prepareInstanceForNextOperation();
        reject(failedToRecordError());
      };
      this.mediaRecorder.onstop = async () => {
        const mimeType = VoiceRecorderImpl.getSupportedMimeType();
        if (mimeType == null) {
          this.prepareInstanceForNextOperation();
          reject(failedToFetchRecordingError());
          return;
        }
        const blobVoiceRecording = new Blob(this.chunks, { type: mimeType });
        if (blobVoiceRecording.size <= 0) {
          this.prepareInstanceForNextOperation();
          reject(emptyRecordingError());
          return;
        }
        if (this.buffer.length) {
          this.sendAudioData(mimeType, _this);
        }
        const recordDataBase64 = await VoiceRecorderImpl.blobToBase64(blobVoiceRecording);
        const recordingDuration = await getBlobDuration(blobVoiceRecording);
        this.prepareInstanceForNextOperation();
        resolve({ value: { recordDataBase64, mimeType, msDuration: recordingDuration * 1000 } });
      };
      this.mediaRecorder.ondataavailable = (event: any) => {
        this.chunks.push(event.data);
        this.handleDataAvailable(event.data, _this);
      };
      this.mediaRecorder.start(0);
    });
    return successResponse();
  }

  private handleDataAvailable(blob: Blob, _this: any) {
    this.buffer.push(blob);
    this.bufferSize += blob.size;

    // Check if we have accumulated 4KB or more
    if (this.bufferSize >= this.chunkSize || (!this.firstChunk && this.bufferSize >= this.firstChunkSize)) {
      this.firstChunk = true;
      this.sendAudioData(blob.type, _this);

      // Reset buffer
      this.buffer = [];
      this.bufferSize = 0;
    }
  }

  private sendAudioData(type: string, _this: any) {
    // Concatenate buffered Blobs into a single Blob
    const combinedBlob = new Blob(this.buffer, { type });

    // Convert Blob to Base64 and emit as a chunk
    const reader = new FileReader();
    reader.onloadend = () => {
      const base64data = reader.result as string;
      const audioChunkEvent: AudioChunkEvent = { data: base64data.split(',')[1] }; // Base64-encoded audio
      _this.notifyListeners('onAudioChunk', audioChunkEvent); // Emit audio chunk event
    };
    reader.readAsDataURL(combinedBlob);
  }

  private onFailedToStartRecording(): GenericResponse {
    this.prepareInstanceForNextOperation();
    throw failedToRecordError();
  }

  private static blobToBase64(blob: Blob): Promise<Base64String> {
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        const recordingResult = String(reader.result);
        const splitResult = recordingResult.split('base64,');
        const toResolve = splitResult.length > 1 ? splitResult[1] : recordingResult;
        resolve(toResolve.trim());
      };
      reader.readAsDataURL(blob);
    });
  }

  private prepareInstanceForNextOperation(): void {
    if (this.mediaRecorder != null && this.mediaRecorder.state === 'recording') {
      try {
        this.mediaRecorder.stop();
      } catch (error) {
        console.warn('While trying to stop a media recorder, an error was thrown', error);
      }
    }
    this.pendingResult = neverResolvingPromise();
    this.mediaRecorder = null;
    this.chunks = [];
    this.buffer = [];
    this.bufferSize = 0;
    this.firstChunk = false;
  }
}
