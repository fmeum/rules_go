package hermeticity

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

var execrootBytes = []byte("/execroot/")

func TestNoExecrootPaths(t *testing.T) {
	// Verify that the compiled stdlib contains no references to absolute paths.
	stdlibPkgDir, err := runfiles.Rlocation("io_bazel_rules_go/stdlib_/pkg")
	if err != nil {
		t.Fatal(err)
	}
	numAbsolutePaths := 0
	var visit fs.WalkDirFunc
	visit = func(path string, d fs.DirEntry, err error) error {
		content, err := os.ReadFile(path)
		pos := -1
		for {
			start := pos + 1
			pos = bytes.Index(content[start:], execrootBytes)
			if pos == -1 {
				break
			}
			pos += start
			begin := pos - 150
			if begin < 0 {
				begin = 0
			}
			end := pos + 150
			if end > len(content) {
				end = len(content)
			}
			t.Logf("%s leaks an absolute path:\n%q", path, content[begin:end])
			numAbsolutePaths++
		}
		return nil
	}
	if err = filepath.WalkDir(stdlibPkgDir, visit); err != nil {
		t.Fatal(err)
	}
	if numAbsolutePaths > 0 {
		t.Fatalf("Found %d absolute paths", numAbsolutePaths)
	}
}
