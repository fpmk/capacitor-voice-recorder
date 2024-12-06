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
  private buffer: ArrayBuffer = new ArrayBuffer(0);
  private firstChunk = false;
  private bufferSize = 0;
  private chunkSize = 4096; // 4KB in bytes
  private firstChunkSize = 44; // 44 bytes

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
      this.sendAudioData(this.int8ArrayToBase64(this.buffer), 'audio/mp3', _this);
      // Reset buffer
      this.buffer = new ArrayBuffer(0);
      this.bufferSize = 0;
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

  public async startRecording(): Promise<GenericResponse> {
    if (this._recorder.state === 1) {
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
    this.firstChunk = false;
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
    } else if (this._recorder.state === 1) {
      this._recorder.pause();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public resumeRecording(): Promise<GenericResponse> {
    if (this._recorder == null) {
      throw recordingHasNotStartedError();
    } else if (this._recorder.state === 2) {
      this._recorder.resume();
      return Promise.resolve(successResponse());
    } else {
      return Promise.resolve(failureResponse());
    }
  }

  public getCurrentStatus(): Promise<CurrentRecordingStatus> {
    if (this._recorder == null) {
      return Promise.resolve({ status: RecordingStatus.NONE });
    } else if (this._recorder.state === 1) {
      return Promise.resolve({ status: RecordingStatus.RECORDING });
    } else if (this._recorder.state === 2) {
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

  private concatenateArrayBuffers(buffer1: ArrayBuffer, buffer2: ArrayBuffer) {
    // Create a new ArrayBuffer with a combined size
    const totalLength = buffer1.byteLength + buffer2.byteLength;
    const result = new Uint8Array(totalLength);

    // Copy the first buffer into the result
    result.set(new Uint8Array(buffer1), 0);

    // Copy the second buffer into the result
    result.set(new Uint8Array(buffer2), buffer1.byteLength);

    // Return the concatenated ArrayBuffer
    return result.buffer;
  }

  private handleDataAvailable(blob: ArrayBuffer, _this: any) {
    this.buffer = this.concatenateArrayBuffers(this.buffer, blob);
    this.bufferSize += blob.byteLength;
    if (this.bufferSize >= this.chunkSize || (!this.firstChunk && this.bufferSize >= this.firstChunkSize)) {
      this.firstChunk = true;
      this.sendAudioData(this.int8ArrayToBase64(this.buffer), 'audio/mp3', _this);

      // Reset buffer
      this.buffer = new ArrayBuffer(0);
      this.bufferSize = 0;
    }
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

  private prepareInstanceForNextOperation(): void {
    if (this._recorder != null && this._recorder.state === 1) {
      try {
        this._recorder.stop();
      } catch (error) {
        console.warn('While trying to stop a media recorder, an error was thrown', error);
      }
    }
    this.pendingResult = neverResolvingPromise();
  }
}
