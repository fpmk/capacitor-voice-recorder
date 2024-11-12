package com.tchvu3.capacitorvoicerecorder;

import android.annotation.SuppressLint;
import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;

import java.io.File;
import java.io.IOException;

public class CustomMediaRecorder {

  private final Context context;
  private AudioRecord audioRecorder;
  private int bufferSize;
  private File outputFile;
  private boolean isStreaming = false;
  private boolean firstHeaders = false;
  private CurrentRecordingStatus currentRecordingStatus = CurrentRecordingStatus.NONE;
  private AudioChunkListener chunkListener;

  public CustomMediaRecorder(Context context) throws IOException {
    this.context = context;
    generateAudioRecorder();
  }

  @SuppressLint("MissingPermission")
  private void generateAudioRecorder() throws IOException {
    bufferSize = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
    audioRecorder = new AudioRecord(MediaRecorder.AudioSource.MIC, 16000, AudioFormat.CHANNEL_IN_MONO,
                                    AudioFormat.ENCODING_PCM_16BIT, bufferSize);
    setRecorderOutputFile();
  }

  private void setRecorderOutputFile() throws IOException {
    File outputDir = context.getCacheDir();
    outputFile = File.createTempFile("voice_record_temp", ".wav", outputDir);
//    outputFile.deleteOnExit();
  }

  public void startRecording(AudioChunkListener listener) {
    if (audioRecorder.getState() != AudioRecord.STATE_INITIALIZED) {
      return;
    }
    this.chunkListener = listener;
    this.firstHeaders = false;
    audioRecorder.startRecording();
    currentRecordingStatus = CurrentRecordingStatus.RECORDING;
    isStreaming = true;
    // Start a new thread for streaming audio data in chunks
    new Thread(() -> {
      byte[] buffer = new byte[bufferSize];
      while (isStreaming) {
        int readSize = audioRecorder.read(buffer, 0, buffer.length);
        if (readSize > 0) {
          // Send chunk to listener for real-time streaming
          if (!this.firstHeaders) {
            if (chunkListener != null) {
              chunkListener.onAudioChunk(this.writeWavHeader(16000, 1, AudioFormat.ENCODING_PCM_16BIT), 44);
              this.firstHeaders = true;
            }
          }
          if (chunkListener != null) {
            chunkListener.onAudioChunk(buffer, readSize);
          }
        }
      }
    }).start();
  }

  public void stopRecording() {
    if (isStreaming) {
      isStreaming = false;
      audioRecorder.stop();
      currentRecordingStatus = CurrentRecordingStatus.NONE;
    }
  }

  public boolean pauseRecording() throws NotSupportedOsVersion {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      throw new NotSupportedOsVersion();
    }

    if (currentRecordingStatus == CurrentRecordingStatus.RECORDING) {
      audioRecorder.stop();
      currentRecordingStatus = CurrentRecordingStatus.PAUSED;
      isStreaming = false;
      return true;
    } else {
      return false;
    }
  }

  public boolean resumeRecording() throws NotSupportedOsVersion {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      throw new NotSupportedOsVersion();
    }

    if (currentRecordingStatus == CurrentRecordingStatus.PAUSED) {
      audioRecorder.startRecording();
      currentRecordingStatus = CurrentRecordingStatus.RECORDING;
      isStreaming = true;
      return true;
    } else {
      return false;
    }
  }

  public File getOutputFile() {
    return outputFile;
  }

  public CurrentRecordingStatus getCurrentStatus() {
    return currentRecordingStatus;
  }

  public boolean deleteOutputFile() {
//    return outputFile.delete();
    return true;
  }

  public static boolean canPhoneCreateMediaRecorder(Context context) {
    return true;
  }

  private static boolean canPhoneCreateMediaRecorderWhileHavingPermission(Context context) {
    CustomMediaRecorder tempMediaRecorder = null;
    try {
      tempMediaRecorder = new CustomMediaRecorder(context);
      tempMediaRecorder.startRecording(null);
      tempMediaRecorder.stopRecording();
      return true;
    } catch (Exception exp) {
      return exp.getMessage().startsWith("stop failed");
    } finally {
//      if (tempMediaRecorder != null)
//        tempMediaRecorder.deleteOutputFile();
    }
  }

  public interface AudioChunkListener {
    void onAudioChunk(byte[] audioData, int size);
  }

  private byte[] writeWavHeader(int sampleRate, int channels, int audioFormat) {
    // Write WAV header (44 bytes)
    int bitsPerSample = audioFormat == AudioFormat.ENCODING_PCM_16BIT ? 16 : 8;
    byte[] header = new byte[44];

    // RIFF header
    header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
    // Chunk size (will update later)
    header[4] = 0; header[5] = 0; header[6] = 0; header[7] = 0;
    // WAVE header
    header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
    // fmt subchunk
    header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
    // Subchunk1 size (16 for PCM)
    header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
    // Audio format (1 for PCM)
    header[20] = 1; header[21] = 0;
    // Channels
    header[22] = (byte) channels; header[23] = 0;
    // Sample rate
    header[24] = (byte) (sampleRate & 0xff);
    header[25] = (byte) ((sampleRate >> 8) & 0xff);
    header[26] = (byte) ((sampleRate >> 16) & 0xff);
    header[27] = (byte) ((sampleRate >> 24) & 0xff);
    // Byte rate
    int byteRate = sampleRate * channels * bitsPerSample / 8;
    header[28] = (byte) (byteRate & 0xff);
    header[29] = (byte) ((byteRate >> 8) & 0xff);
    header[30] = (byte) ((byteRate >> 16) & 0xff);
    header[31] = (byte) ((byteRate >> 24) & 0xff);
    // Block align
    header[32] = (byte) (channels * bitsPerSample / 8); header[33] = 0;
    // Bits per sample
    header[34] = (byte) bitsPerSample; header[35] = 0;
    // data subchunk
    header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
    // Subchunk2 size (will update later)
    header[40] = 0; header[41] = 0; header[42] = 0; header[43] = 0;

    return header;
  }

}
