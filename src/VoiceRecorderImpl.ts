import type { AudioChunkEvent, CurrentRecordingStatus, GenericResponse, RecordingData } from './definitions';
import { RecordingStatus } from './definitions';
import {
  alreadyRecordingError,
  couldNotQueryPermissionStatusError,
  deviceCannotVoiceRecordError,
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
  private pendingResult: Promise<RecordingData> = neverResolvingPromise();
  private _recorder: any;

  constructor(_recorder: any, _this: any) {
    this._recorder = _recorder;
    this._recorder.onstart = () => {
      console.log('Starting recording *********************');
    };
    this._recorder.onerror = (err: any) => {
      console.log(err);
      this.prepareInstanceForNextOperation();
      return failedToRecordError();
    };
    this._recorder.onstop = async () => {
      this.prepareInstanceForNextOperation();
      return Promise.resolve();
    };
    this._recorder.ondataavailable = (event: any) => {
      this.handleDataAvailable(event, _this);
    };
  }

  public static async canDeviceVoiceRecord(): Promise<GenericResponse> {
    if (navigator?.mediaDevices?.getUserMedia == null || VoiceRecorderImpl.getSupportedMimeType() == null) {
      return failureResponse();
    } else {
      return successResponse();
    }
  }

  public async startRecording(_this: any): Promise<GenericResponse> {
    if (this._recorder.state === 'RECORDING') {
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
    this._recorder.start();
    return successResponse();
  }

  public async stopRecording(): Promise<RecordingData> {
    if (this._recorder == null) {
      throw recordingHasNotStartedError();
    }
    try {
      this._recorder.stop();
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
    if (this._recorder == null) {
      throw recordingHasNotStartedError();
    } else if (this._recorder.state === 'RECORDING') {
      this._recorder.pause();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public resumeRecording(): Promise<GenericResponse> {
    if (this._recorder == null) {
      throw recordingHasNotStartedError();
    } else if (this._recorder.state === 'PAUSED') {
      this._recorder.resume();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public getCurrentStatus(): Promise<CurrentRecordingStatus> {
    if (this._recorder == null) {
      return Promise.resolve({ status: RecordingStatus.NONE });
    } else if (this._recorder.state === 'RECORDING') {
      return Promise.resolve({ status: RecordingStatus.RECORDING });
    } else if (this._recorder.state === 'PAUSED') {
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

  // private onSuccessfullyStartedRecording(_this: any): GenericResponse {
  //   return successResponse();
  // }
  //
  private handleDataAvailable(blob: ArrayBuffer, _this: any) {
    this.sendAudioData(this.int8ArrayToBase64(blob), 'audio/mp3', _this);
  }

  private int8ArrayToBase64(int8Array: ArrayBuffer): string {
    const uint8Array = new Uint8Array(int8Array);
    const binaryString = Array.from(uint8Array)
      .map((byte) => String.fromCharCode(byte))
      .join('');
    return btoa(binaryString);
  }

  private sendAudioData(base64: string, type: string, _this: any) {
    const audioChunkEvent: AudioChunkEvent = { data: base64, mimeType: type }; // Base64-encoded audio
    _this.notifyListeners('onAudioChunk', audioChunkEvent); // Emit audio chunk event
  }

  // private onFailedToStartRecording(): GenericResponse {
  //   this.prepareInstanceForNextOperation();
  //   throw failedToRecordError();
  // }

  private prepareInstanceForNextOperation(): void {
    if (this._recorder != null && this._recorder.state === 'RECORDING') {
      try {
        this._recorder.stop();
      } catch (error) {
        console.warn('While trying to stop a media recorder, an error was thrown', error);
      }
    }
    this.pendingResult = neverResolvingPromise();
  }
}
