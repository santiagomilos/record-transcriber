package progress

import (
	"bytes"
	"errors"
	"testing"
	"time"
)

func TestJSONWritesOneObjectPerLine(t *testing.T) {
	var buf bytes.Buffer
	emitter := &JSON{W: &buf}

	emitter.Emit(Input("reunion.mp4", 963*time.Second))
	emitter.Emit(Stage(StageExtract))
	emitter.Emit(Stage(StageTranscribe))
	emitter.Emit(Progress(37))
	emitter.Emit(Transcript("es", 167, 103*time.Second))
	emitter.Emit(Output("txt", "/recordings/reunion.txt"))
	emitter.Emit(Summary("minuta"))
	emitter.Emit(Output("summary", "/recordings/reunion.summary.md"))

	want := `{"event":"input","name":"reunion.mp4","duration_ms":963000}
{"event":"stage","stage":"extract"}
{"event":"stage","stage":"transcribe"}
{"event":"progress","percent":37}
{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}
{"event":"output","kind":"txt","path":"/recordings/reunion.txt"}
{"event":"stage","stage":"summary","name":"minuta"}
{"event":"output","kind":"summary","path":"/recordings/reunion.summary.md"}
`
	if got := buf.String(); got != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestJSONReportsModelDownloadsInBytes(t *testing.T) {
	var buf bytes.Buffer
	emitter := &JSON{W: &buf}

	emitter.Emit(Model("large-v3-turbo", 0, 1677721600, false))
	emitter.Emit(Model("large-v3-turbo", 734003200, 1677721600, false))
	emitter.Emit(Model("large-v3-turbo", 1677721600, 1677721600, true))

	want := `{"event":"model","name":"large-v3-turbo","bytes_total":1677721600}
{"event":"model","name":"large-v3-turbo","bytes_done":734003200,"bytes_total":1677721600}
{"event":"model","name":"large-v3-turbo","bytes_done":1677721600,"bytes_total":1677721600,"done":true}
`
	if got := buf.String(); got != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestJSONReportsErrors(t *testing.T) {
	var buf bytes.Buffer
	emitter := &JSON{W: &buf}

	emitter.Emit(Error(errors.New("cannot read input file: no such file or directory")))

	want := `{"event":"error","message":"cannot read input file: no such file or directory"}
`
	if got := buf.String(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTextRendersTheNarrationATerminalHasAlwaysSeen(t *testing.T) {
	var buf bytes.Buffer
	emitter := &Text{W: &buf}

	emitter.Emit(Input("reunion.mp4", 963*time.Second))
	emitter.Emit(Stage(StageExtract))
	emitter.Emit(Stage(StageTranscribe))
	emitter.Emit(Transcript("es", 167, 103*time.Second))
	emitter.Emit(Summary("minuta"))

	want := "Input: reunion.mp4 (16m3s)\n" +
		"Extracting audio...\n" +
		"Transcribing...\n" +
		"Done in 1m43s (language: es, 167 segments)\n" +
		"Generating minuta...\n"
	if got := buf.String(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTextPrintsTheDownloadBannerOncePerModel(t *testing.T) {
	var buf bytes.Buffer
	emitter := &Text{W: &buf}

	emitter.Emit(Model("large-v3-turbo", 0, 1677721600, false))
	emitter.Emit(Model("large-v3-turbo", 734003200, 1677721600, false))
	emitter.Emit(Model("large-v3-turbo", 1677721600, 1677721600, true))

	// The final event closes the in-place progress line with a newline rather
	// than repainting it at 100%, which is what the tool has always done.
	want := "Downloading model large-v3-turbo (this happens once)\n" +
		"\r  43% (700/1600 MiB)" +
		"\n"
	if got := buf.String(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTextReportsBytesWhenTheServerSentNoContentLength(t *testing.T) {
	var buf bytes.Buffer
	emitter := &Text{W: &buf}

	emitter.Emit(Model("silero-v5.1.2", 0, 0, false))
	emitter.Emit(Model("silero-v5.1.2", 5242880, 0, false))

	want := "Downloading model silero-v5.1.2 (this happens once)\n" +
		"\r  5 MiB"
	if got := buf.String(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTextIgnoresOutputAndErrorBecauseTheCallerAlreadyReportsThem(t *testing.T) {
	var buf bytes.Buffer
	emitter := &Text{W: &buf}

	emitter.Emit(Output("txt", "/recordings/reunion.txt"))
	emitter.Emit(Error(errors.New("whisper-cli is not on your PATH")))

	if got := buf.String(); got != "" {
		t.Errorf("got %q, want no output", got)
	}
}
