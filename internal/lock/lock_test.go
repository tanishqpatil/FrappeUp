package lock

import "testing"

func TestPickCommitPrefersDereferencedAnnotatedTag(t *testing.T) {
	output := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/v1.0.0\n" +
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\trefs/tags/v1.0.0^{}\n"
	if got, want := pickCommit(output, "v1.0.0", "tag"), "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; got != want {
		t.Fatalf("commit = %s, want %s", got, want)
	}
}

func TestPickCommitFindsBranch(t *testing.T) {
	output := "cccccccccccccccccccccccccccccccccccccccc\trefs/heads/version-16\n"
	if got, want := pickCommit(output, "version-16", "branch"), "cccccccccccccccccccccccccccccccccccccccc"; got != want {
		t.Fatalf("commit = %s, want %s", got, want)
	}
}
