// Package format renders a transcript as plain text or as subtitles, and reads
// those renderings back.
package format

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/santiagomilos/record-transcriber/internal/asr"
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

// ReadSRT parses SubRip subtitles back into a transcript, the inverse of
// WriteSRT. Reading a transcript that already exists is what lets a summary be
// regenerated without decoding the audio again.
//
// Cue numbers are ignored rather than trusted: they carry no information the
// order of the file does not already give.
func ReadSRT(r io.Reader) (*asr.Result, error) {
	result := &asr.Result{}
	var (
		cue   *asr.Segment
		lines []string
	)
	flush := func() {
		if cue == nil {
			return
		}
		cue.Text = strings.Join(lines, " ")
		if cue.Text != "" {
			result.Segments = append(result.Segments, *cue)
		}
		cue, lines = nil, nil
	}

	sc := bufio.NewScanner(r)
	// Subtitle text is short, but a malformed file can present as one long line.
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		switch {
		case line == "":
			flush()
		case strings.Contains(line, "-->"):
			flush()
			start, end, err := parseCue(line)
			if err != nil {
				return nil, fmt.Errorf("line %d: %w", n, err)
			}
			cue = &asr.Segment{Start: start, End: end}
		case cue != nil:
			lines = append(lines, line)
		}
		// Anything else is a cue number, or text before the first timing line.
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	flush()

	if len(result.Segments) == 0 {
		return nil, fmt.Errorf("no subtitle cues found")
	}
	return result, nil
}

// ReadText parses the plain text rendering back into a transcript, the inverse
// of WriteText. That rendering carries no timings, so the segments come back
// without them.
func ReadText(r io.Reader) (*asr.Result, error) {
	result := &asr.Result{}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		if line := strings.TrimSpace(sc.Text()); line != "" {
			result.Segments = append(result.Segments, asr.Segment{Text: line})
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(result.Segments) == 0 {
		return nil, fmt.Errorf("no text found")
	}
	return result, nil
}

// parseCue splits a "start --> end" line into its two timestamps.
func parseCue(line string) (start, end time.Duration, err error) {
	from, to, ok := strings.Cut(line, "-->")
	if !ok {
		return 0, 0, fmt.Errorf("malformed cue %q", line)
	}
	if start, err = parseTimestamp(strings.TrimSpace(from)); err != nil {
		return 0, 0, err
	}
	// A cue may carry positioning settings after its end time. WriteVTT emits
	// none, but a file written elsewhere can.
	to, _, _ = strings.Cut(strings.TrimSpace(to), " ")
	if end, err = parseTimestamp(to); err != nil {
		return 0, 0, err
	}
	return start, end, nil
}

// parseTimestamp reads HH:MM:SS,mmm, accepting the period VTT uses in place of
// the comma SRT uses.
func parseTimestamp(s string) (time.Duration, error) {
	malformed := fmt.Errorf("malformed timestamp %q (want HH:MM:SS,mmm)", s)

	clock, millis, ok := strings.Cut(strings.Replace(s, ",", ".", 1), ".")
	if !ok || len(millis) != 3 {
		return 0, malformed
	}
	parts := strings.Split(clock, ":")
	if len(parts) != 3 {
		return 0, malformed
	}

	units := make([]int, 0, 4)
	for _, p := range []string{parts[0], parts[1], parts[2], millis} {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return 0, malformed
		}
		units = append(units, n)
	}
	return time.Duration(units[0])*time.Hour +
		time.Duration(units[1])*time.Minute +
		time.Duration(units[2])*time.Second +
		time.Duration(units[3])*time.Millisecond, nil
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
