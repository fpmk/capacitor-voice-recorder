package com.tchvu3.capacitorvoicerecorder;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

public class CustomMediaRecorder {

    private final Context context;
    private AudioRecord audioRecorder;
    private int bufferSize;
    private File outputFile;
    private FileOutputStream fileOutputStream;
    private boolean isStreaming = false;
    private CurrentRecordingStatus currentRecordingStatus = CurrentRecordingStatus.NONE;
    private AudioChunkListener chunkListener;

    public CustomMediaRecorder(Context context) throws IOException {
        this.context = context;
        generateAudioRecorder();
    }

    private void generateAudioRecorder() throws IOException {
        bufferSize = AudioRecord.getMinBufferSize(44100, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        audioRecorder = new AudioRecord(MediaRecorder.AudioSource.MIC, 44100, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, bufferSize);
        setRecorderOutputFile();
    }

    private void setRecorderOutputFile() throws IOException {
        File outputDir = context.getCacheDir();
        outputFile = File.createTempFile("voice_record_temp", ".pcm", outputDir);
        outputFile.deleteOnExit();
        fileOutputStream = new FileOutputStream(outputFile);
    }

    public void startRecording(AudioChunkListener listener) {
        if (audioRecorder.getState() != AudioRecord.STATE_INITIALIZED) {
            return;
        }
        this.chunkListener = listener;
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
                    if (chunkListener != null) {
                        chunkListener.onAudioChunk(buffer, readSize);
                    }
                    // Write to file for later access if needed
                    try {
                        fileOutputStream.write(buffer, 0, readSize);
                    } catch (IOException e) {
                        e.printStackTrace();
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
            try {
                fileOutputStream.close();
            } catch (IOException e) {
                e.printStackTrace();
    }
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
        return outputFile.delete();
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
            if (tempMediaRecorder != null) tempMediaRecorder.deleteOutputFile();
        }
    }

    public interface AudioChunkListener {
        void onAudioChunk(byte[] audioData, int size);
    }
}
