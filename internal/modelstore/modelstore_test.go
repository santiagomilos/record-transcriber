package modelstore

import "testing"

func TestModelURLResolvesTranscriptionModelsToWhisperRepo(t *testing.T) {
	got := modelURL("ggml-large-v3-turbo.bin")
	want := "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestModelURLResolvesVADModelsToVADRepo(t *testing.T) {
	got := modelURL("ggml-silero-v5.1.2.bin")
	want := "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestVADModelConstantResolvesToVADRepo(t *testing.T) {
	got := modelURL("ggml-" + VADModel + ".bin")
	want := "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
