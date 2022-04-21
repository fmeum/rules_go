//go:build go1.18
// +build go1.18

package bzltestutil

import (
	"io"
	"reflect"
	"time"
)

// Copied from
// https://github.com/golang/go/blob/4aa1efed4853ea067d665a952eee77c52faac774/src/testing/testing.go#L1622
type testDeps interface {
	ImportPath() string
	MatchString(pat, str string) (bool, error)
	SetPanicOnExit0(bool)
	StartCPUProfile(io.Writer) error
	StopCPUProfile()
	StartTestLog(io.Writer)
	StopTestLog() error
	WriteProfileTo(string, io.Writer, int) error
	CoordinateFuzzing(time.Duration, int64, time.Duration, int64, int, []corpusEntry, []reflect.Type, string, string) error
	RunFuzzWorker(func(corpusEntry) error) error
	ReadCorpus(string, []reflect.Type) ([]corpusEntry, error)
	CheckCorpus([]any, []reflect.Type) error
	ResetCoverage()
	SnapshotCoverage()
}

// Copied from
// https://github.com/golang/go/blob/4aa1efed4853ea067d665a952eee77c52faac774/src/testing/fuzz.go#L91
type corpusEntry = struct {
	Parent     string
	Path       string
	Data       []byte
	Values     []any
	Generation int
	IsSeed     bool
}

