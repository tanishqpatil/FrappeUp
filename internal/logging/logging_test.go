package logging

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestTailReturnsMostRecentEntries(t *testing.T) {
	path := filepath.Join(t.TempDir(), "logs", "cli.jsonl")
	logger, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, event := range []string{"first", "second", "third"} {
		if err := logger.Info(event, "completed", nil); err != nil {
			t.Fatal(err)
		}
	}
	if err := logger.Close(); err != nil {
		t.Fatal(err)
	}
	output, err := Tail(path, 2)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(output, `"event":"first"`) || !strings.Contains(output, `"event":"second"`) || !strings.Contains(output, `"event":"third"`) {
		t.Fatalf("unexpected tail output: %s", output)
	}
}

func TestRedactRemovesURLCredentialsAndTokens(t *testing.T) {
	input := "fetch https://user:password@example.com/repo?access_token=secret-value&safe=value"
	got := Redact(input)
	if strings.Contains(got, "user:password") || strings.Contains(got, "secret-value") {
		t.Fatalf("credentials were not redacted: %s", got)
	}
	if !strings.Contains(got, "https://***@example.com") || !strings.Contains(got, "safe=value") {
		t.Fatalf("unexpected redacted value: %s", got)
	}
}
