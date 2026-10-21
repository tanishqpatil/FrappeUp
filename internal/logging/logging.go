package logging

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

var (
	urlCredentials = regexp.MustCompile(`(?i)(https?://)[^\s/@]+@`)
	sensitiveQuery = regexp.MustCompile(`(?i)([?&](?:access_)?token|[?&](?:client_)?secret|[?&]password)=([^\s&]+)`)
)

// Entry is one append-only operational record. Configuration values and
// credentials are intentionally never written by this package.
type Entry struct {
	Timestamp time.Time      `json:"timestamp"`
	Level     string         `json:"level"`
	Event     string         `json:"event"`
	Message   string         `json:"message"`
	Fields    map[string]any `json:"fields,omitempty"`
}

type Logger struct {
	file    *os.File
	encoder *json.Encoder
	mu      sync.Mutex
}

func DefaultPath(envFile string) string {
	return filepath.Join(filepath.Dir(envFile), ".frappe1tap", "logs", "cli.jsonl")
}

func GlobalPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("find user home for logs: %w", err)
	}
	return filepath.Join(home, ".frappe1tap", "logs", "cli.jsonl"), nil
}

func Open(path string) (*Logger, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, fmt.Errorf("create log directory: %w", err)
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open log file: %w", err)
	}
	return &Logger{file: file, encoder: json.NewEncoder(file)}, nil
}

func (l *Logger) Info(event, message string, fields map[string]any) error {
	return l.write("info", event, message, fields)
}

func (l *Logger) Error(event string, err error) error {
	return l.write("error", event, Redact(err.Error()), nil)
}

func (l *Logger) Close() error {
	return l.file.Close()
}

func Redact(message string) string {
	message = urlCredentials.ReplaceAllString(message, "${1}***@")
	return sensitiveQuery.ReplaceAllString(message, "${1}=***")
}

func (l *Logger) write(level, event, message string, fields map[string]any) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.encoder.Encode(Entry{
		Timestamp: time.Now().UTC(), Level: level, Event: event, Message: message, Fields: fields,
	})
}

func Tail(path string, lines int) (string, error) {
	if lines < 1 {
		return "", fmt.Errorf("line count must be at least 1")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	entries := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(entries) > lines {
		entries = entries[len(entries)-lines:]
	}
	return strings.Join(entries, "\n") + "\n", nil
}

// Follow writes records appended after this function starts until the context
// is cancelled. Polling keeps this portable across macOS, Linux, and Windows.
func Follow(ctx context.Context, path string, output io.Writer) error {
	var offset int64
	if info, err := os.Stat(path); err == nil {
		offset = info.Size()
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			file, err := os.Open(path)
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil {
				return err
			}
			info, err := file.Stat()
			if err != nil {
				file.Close()
				return err
			}
			if info.Size() < offset {
				offset = 0
			}
			if _, err := file.Seek(offset, io.SeekStart); err != nil {
				file.Close()
				return err
			}
			written, copyErr := io.Copy(output, file)
			closeErr := file.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
			offset += written
		}
	}
}
