// Package format renders a transcript as plain text or as subtitles.
package format

import (
	"fmt"
	"io"
	"time"

	"github.com/santi/record-transcriber/internal/asr"
)

// WriteText writes one segment per line, without timestamps.
func WriteText(w io.Writer, r *asr.Result) error {
	for _, s := range r.Segments {
		if _, err := fmt.Fprintln(w, s.Text); err != nil {
			return err
		}
	}
	return nil
}

// WriteSRT writes SubRip subtitles: blocks numbered from 1, with a comma
// before the milliseconds.
func WriteSRT(w io.Writer, r *asr.Result) error {
	for i, s := range r.Segments {
		_, err := fmt.Fprintf(w, "%d\n%s --> %s\n%s\n\n",
			i+1, timestamp(s.Start, ','), timestamp(s.End, ','), s.Text)
		if err != nil {
			return err
		}
	}
	return nil
}

// WriteVTT writes WebVTT subtitles: a WEBVTT header, no cue numbers, and a
// period before the milliseconds.
func WriteVTT(w io.Writer, r *asr.Result) error {
	if _, err := fmt.Fprint(w, "WEBVTT\n\n"); err != nil {
		return err
	}
	for _, s := range r.Segments {
		_, err := fmt.Fprintf(w, "%s --> %s\n%s\n\n",
			timestamp(s.Start, '.'), timestamp(s.End, '.'), s.Text)
		if err != nil {
			return err
		}
	}
	return nil
}

// timestamp renders HH:MM:SS<sep>mmm, the shape both subtitle formats use.
func timestamp(d time.Duration, sep byte) string {
	if d < 0 {
		d = 0
	}
	ms := d.Milliseconds()
	return fmt.Sprintf("%02d:%02d:%02d%c%03d",
		ms/3_600_000, ms/60_000%60, ms/1_000%60, sep, ms%1_000)
}
