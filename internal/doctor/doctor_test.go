package doctor

import (
	"context"
	"errors"
	"testing"
)

type fakeRunner struct {
	fail map[string]error
}

func (f fakeRunner) Run(_ context.Context, _ string, args ...string) (string, error) {
	key := args[0]
	if err := f.fail[key]; err != nil {
		return "not ready", err
	}
	return "ready", nil
}

func TestRunIsReadyWhenAllChecksPass(t *testing.T) {
	report := Run(context.Background(), fakeRunner{})
	if !report.Ready || report.Error() != nil {
		t.Fatalf("expected ready report: %+v", report)
	}
}

func TestRunReportsFailedRequiredCheck(t *testing.T) {
	report := Run(context.Background(), fakeRunner{fail: map[string]error{"info": errors.New("daemon unavailable")}})
	if report.Ready || report.Error() == nil {
		t.Fatalf("expected failed report: %+v", report)
	}
	if report.Checks[3].Fix == "" {
		t.Fatal("expected remediation advice")
	}
}
