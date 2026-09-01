// Package modelstore resolves ggml Whisper models, downloading and caching
// them on first use.
package modelstore

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// DefaultModel is the speed/accuracy sweet spot on Apple Silicon: ~3% WER at
// roughly 10x real time, for 1.6 GB on disk.
const DefaultModel = "large-v3-turbo"

// VADModel is the Silero voice-activity model whisper-cli needs before --vad
// will do anything; without it the engine aborts. It is a small download.
const VADModel = "silero-v5.1.2"

// Transcription models and VAD models are published in different Hugging Face
// repositories.
const (
	whisperBaseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
	vadBaseURL     = "https://huggingface.co/ggml-org/whisper-vad/resolve/main/"
)

// modelURL resolves where a ggml file is published.
func modelURL(filename string) string {
	if strings.HasPrefix(filename, "ggml-silero-") {
		return vadBaseURL + filename
	}
	return whisperBaseURL + filename
}

// CacheDir returns the directory models are cached in.
func CacheDir() (string, error) {
	dir, err := os.UserCacheDir()
	if err != nil {
		return "", fmt.Errorf("modelstore: locate cache directory: %w", err)
	}
	return filepath.Join(dir, "record-transcriber", "models"), nil
}

// Download reports how far a model download has got. BytesTotal is zero when
// the server sent no content length.
type Download struct {
	Model      string
	BytesDone  int64
	BytesTotal int64
	// Done marks the final report for a download.
	Done bool
}

// EnsureModel returns the path to the named ggml model, downloading it into the
// cache if it is not there yet. report, which may be nil, is called once when a
// download starts, then at most once a second while it runs, then once with
// Done set. It is not called at all when the model is already cached.
func EnsureModel(ctx context.Context, name string, report func(Download)) (string, error) {
	if name == "" {
		name = DefaultModel
	}

	dir, err := CacheDir()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("modelstore: create cache directory: %w", err)
	}

	filename := "ggml-" + name + ".bin"
	path := filepath.Join(dir, filename)

	if info, err := os.Stat(path); err == nil && info.Size() > 0 {
		return path, nil
	}

	if err := download(ctx, modelURL(filename), path, name, report); err != nil {
		return "", err
	}
	return path, nil
}

// download fetches url into path. It writes to a .part file and renames on
// success, so an interrupted download never leaves a truncated model behind
// that would later fail deep inside whisper-cli.
func download(ctx context.Context, url, path, model string, report func(Download)) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("modelstore: build request: %w", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("modelstore: download %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("modelstore: download %s: unexpected status %s", url, resp.Status)
	}

	partPath := path + ".part"
	f, err := os.Create(partPath)
	if err != nil {
		return fmt.Errorf("modelstore: create %s: %w", partPath, err)
	}

	var dst io.Writer = f
	var counter *progressCounter
	if report != nil {
		report(Download{Model: model, BytesTotal: resp.ContentLength})
		counter = &progressCounter{
			model:  model,
			total:  resp.ContentLength,
			report: report,
			last:   time.Now(),
		}
		dst = io.MultiWriter(f, counter)
	}

	if _, err := io.Copy(dst, resp.Body); err != nil {
		f.Close()
		os.Remove(partPath)
		return fmt.Errorf("modelstore: write %s: %w", partPath, err)
	}
	if err := f.Close(); err != nil {
		os.Remove(partPath)
		return fmt.Errorf("modelstore: close %s: %w", partPath, err)
	}
	if counter != nil {
		report(Download{Model: model, BytesDone: counter.written, BytesTotal: counter.total, Done: true})
	}

	if err := os.Rename(partPath, path); err != nil {
		os.Remove(partPath)
		return fmt.Errorf("modelstore: install model: %w", err)
	}
	return nil
}

// progressCounter reports download progress, throttled so it does not flood a
// terminal, a log file, or an event stream.
type progressCounter struct {
	model   string
	total   int64
	written int64
	report  func(Download)
	last    time.Time
}

func (p *progressCounter) Write(b []byte) (int, error) {
	p.written += int64(len(b))
	if time.Since(p.last) < time.Second {
		return len(b), nil
	}
	p.last = time.Now()
	p.report(Download{Model: p.model, BytesDone: p.written, BytesTotal: p.total})
	return len(b), nil
}
