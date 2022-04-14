// Copyright 2022 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package lcov_coverage_test

import (
	"io/ioutil"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bazelbuild/rules_go/go/tools/bazel_testing"
)

func TestMain(m *testing.M) {
	bazel_testing.TestMain(m, bazel_testing.Args{
		Main: `
-- src/BUILD.bazel --
load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "lib",
    srcs = ["lib.go"],
    importpath = "example.com/lib",
    deps = [":other_lib"],
)

go_library(
    name = "other_lib",
    srcs = ["other_lib.go"],
    importpath = "example.com/other_lib",
)

go_test(
    name = "lib_test",
    srcs = ["lib_test.go"],
    deps = [":lib"],
)
-- src/lib.go --
package lib

import (
	"strings"

	"example.com/other_lib"
)

func HelloFromLib(informal bool) string {
	var greetings []string
	if informal {
		greetings = []string{"Hey there, other_lib!"}
	} else {
		greetings = []string{"Good morning, other_lib!"}
	}
	greetings = append(greetings, other_lib.HelloOtherLib(informal))
	return strings.Join(greetings, "\n")
}
-- src/other_lib.go --
package other_lib

func HelloOtherLib(informal bool) string {
	if informal {
		return "Hey there, other_lib!"
	}
	return "Good morning, other_lib!"
}
-- src/lib_test.go --
package lib_test

import (
	"strings"
	"testing"

	"example.com/lib"
)

func TestLib(t *testing.T) {
	if !strings.Contains(lib.HelloFromLib(false), "\n") {
		t.Error("Expected a newline in the output")
	}
}
`,
	})
}

func TestLcovCoverage(t *testing.T) {
	t.Run("without-race", func(t *testing.T) {
		testLcovCoverage(t)
	})

	t.Run("with-race", func(t *testing.T) {
		testLcovCoverage(t, "--@io_bazel_rules_go//go/config:race")
	})
}

func testLcovCoverage(t *testing.T, extraArgs ...string) {
	args := append([]string{
		"coverage",
		"--combined_report=lcov",
		"//src:lib_test",
	}, extraArgs...)

	if err := bazel_testing.RunBazel(args...); err != nil {
		t.Fatal(err)
	}

	individualCoveragePath := filepath.FromSlash("bazel-testlogs/src/lib_test/coverage.dat")
	individualCoverageData, err := ioutil.ReadFile(individualCoveragePath)
	if err != nil {
		t.Fatal(err)
	}
	for _, expectedIndividualCoverage := range expectedIndividualCoverages {
		if !strings.Contains(string(individualCoverageData), expectedIndividualCoverage) {
			t.Errorf(
				"%s: does not contain:\n\n%s\nactual content:\n\n%s",
				individualCoveragePath,
				expectedIndividualCoverage,
				string(individualCoverageData),
			)
		}
	}

	combinedCoveragePath := filepath.FromSlash("bazel-out/_coverage/_coverage_report.dat")
	combinedCoverageData, err := ioutil.ReadFile(combinedCoveragePath)
	if err != nil {
		t.Fatal(err)
	}
	for _, include := range []string{
		"SF:src/lib.go\n",
		"SF:src/other_lib.go\n",
	} {
		if !strings.Contains(string(combinedCoverageData), include) {
			t.Errorf("%s: does not contain %q\n", combinedCoverageData, include)
		}
	}
}

var expectedIndividualCoverages = []string{
	`SF:src/other_lib.go
DA:3,1
DA:4,1
DA:5,0
DA:6,0
DA:7,1
LH:3
LF:5
end_of_record
`,
	`SF:src/lib.go
DA:9,1
DA:10,1
DA:11,1
DA:12,0
DA:13,1
DA:14,1
DA:15,1
DA:16,1
DA:17,1
LH:8
LF:9
end_of_record
`}
