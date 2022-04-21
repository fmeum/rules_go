//go:build !go1.18
// +build !go1.18

package bzltestutil

import (
	"io"
)

// Copied from
// https://github.com/golang/go/blob/f21be2fdc6f1becdbed1592ea0b245cdeedc5ac8/src/testing/testing.go#L1358
type testDeps interface {
	ImportPath() string
	MatchString(pat, str string) (bool, error)
	SetPanicOnExit0(bool)
	StartCPUProfile(io.Writer) error
	StopCPUProfile()
	StartTestLog(io.Writer)
	StopTestLog() error
	WriteProfileTo(string, io.Writer, int) error
}
