// Package media normalizes arbitrary audio and video files into the audio
// format the transcription engine accepts.
package media

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// Binaries the package shells out to.
const (
	FFmpegBinary  = "ffmpeg"
	FFprobeBinary = "ffprobe"
)

// ExtractAudio decodes any container ffmpeg understands into a WAV file at
// wavPath. Mono 16 kHz signed 16-bit is not a preference: it is the only input
// whisper.cpp accepts.
func ExtractAudio(ctx context.Context, inputPath, wavPath string) error {
	if err := os.MkdirAll(filepath.Dir(wavPath), 0o755); err != nil {
		return fmt.Errorf("media: prepare output directory: %w", err)
	}

	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, FFmpegBinary,
		"-hide_banner", "-loglevel", "error", "-y",
		"-i", inputPath,
		"-vn",
		"-ac", "1",
		"-ar", "16000",
		"-c:a", "pcm_s16le",
		wavPath,
	)
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return fmt.Errorf("media: ffmpeg failed on %s: %w: %s", inputPath, err, msg)
		}
		return fmt.Errorf("media: ffmpeg failed on %s: %w", inputPath, err)
	}
	return nil
}

// Duration reports the length of a media file. It returns zero seconds when
// ffprobe cannot determine one, which is not treated as an error: the duration
// is only used for progress reporting.
func Duration(ctx context.Context, path string) (float64, error) {
	out, err := exec.CommandContext(ctx, FFprobeBinary,
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "default=noprint_wrappers=1:nokey=1",
		path,
	).Output()
	if err != nil {
		return 0, fmt.Errorf("media: ffprobe failed on %s: %w", path, err)
	}

	seconds, err := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	if err != nil {
		return 0, nil
	}
	return seconds, nil
}
