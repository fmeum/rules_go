// Copyright 2026 The Bazel Authors. All rights reserved.
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

package exec_platform_test

import (
	"regexp"
	"strings"
	"testing"

	"github.com/bazelbuild/rules_go/go/tools/bazel_testing"
)

// The tools run by GoProtocGen actions (go-protoc and the protoc plugin) have
// to be built for the execution platform of the action, which is resolved for
// an exec group of go_proto_library. This test registers a "remote" execution
// platform before the host platform for which no Go SDK is available, which
// is common for a remote execution setup driven from a workstation. Tools
// built with cfg = "exec" by a target requiring the Go toolchain would land on
// the host, while the exec group running GoProtocGen picks the remote
// platform. As nothing can be executed on the remote platform, the test only
// analyzes the targets and uses a stub protoc to avoid the need for a C++
// toolchain.
var testArgs = bazel_testing.Args{
	ModuleFileSuffix: `
bazel_dep(name = "protobuf", version = "29.0-rc2", repo_name = "com_google_protobuf")
bazel_dep(name = "toolchains_protoc", version = "0.3.4")

register_execution_platforms("//:remote_platform")

register_toolchains("//:stub_proto_toolchain_toolchain")
`,
	Main: `
-- BUILD.bazel --
load("@com_google_protobuf//bazel:proto_library.bzl", "proto_library")
load("@com_google_protobuf//bazel/toolchains:proto_toolchain.bzl", "proto_toolchain")
load("@io_bazel_rules_go//go:def.bzl", "go_binary")
load("@io_bazel_rules_go//proto:def.bzl", "go_proto_library")

platform(
    name = "remote_platform",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:s390x",
    ],
)

go_binary(
    name = "stub_protoc",
    srcs = ["stub_protoc.go"],
)

proto_toolchain(
    name = "stub_proto_toolchain",
    proto_compiler = ":stub_protoc",
)

proto_library(
    name = "foo_proto",
    srcs = ["foo.proto"],
)

go_proto_library(
    name = "foo_go_proto",
    importpath = "example.com/foo",
    protos = [":foo_proto"],
)

-- stub_protoc.go --
package main

func main() {}

-- foo.proto --
syntax = "proto3";

package foo;

option go_package = "example.com/foo";

message Foo {
  int64 x = 1;
}
`,
}

func TestMain(m *testing.M) {
	bazel_testing.TestMain(m, testArgs)
}

func TestToolsFollowActionExecPlatform(t *testing.T) {
	// Only analyze: the remote platform can't execute anything locally.
	if err := bazel_testing.RunBazel("build", "--nobuild", "//:foo_go_proto"); err != nil {
		t.Fatal(err)
	}

	aqueryOut, err := bazel_testing.BazelOutput("aquery", "--output=text", `mnemonic("GoProtocGen", //:foo_go_proto)`)
	if err != nil {
		t.Fatal(err)
	}
	aquery := string(aqueryOut)
	platformMatch := regexp.MustCompile(`(?m)^\s*Execution platform: (\S+)$`).FindStringSubmatch(aquery)
	if platformMatch == nil {
		t.Fatalf("no execution platform found in aquery output:\n%s", aquery)
	}
	platform := normalizeLabel(platformMatch[1])
	// The exec group has no requirements that the remote platform can't
	// satisfy, so it is chosen as the first registered execution platform.
	if want := "//:remote_platform"; platform != want {
		t.Fatalf("GoProtocGen runs on %s, want %s:\n%s", platform, want, aquery)
	}
	inputsMatch := regexp.MustCompile(`(?m)^\s*Inputs: \[(.*)\]$`).FindStringSubmatch(aquery)
	if inputsMatch == nil {
		t.Fatalf("no inputs found in aquery output:\n%s", aquery)
	}
	inputs := strings.Split(inputsMatch[1], ", ")

	// All go_reset_target instances in the transitive closure, together with
	// the target platform they were configured for and the path of the
	// executable they forward.
	cqueryOut, err := bazel_testing.BazelOutput(
		"cquery",
		`kind("go_reset_target", deps(//:foo_go_proto))`,
		"--output=starlark",
		`--starlark:expr="{}|{}|{}".format(target.label, ",".join([str(p) for p in build_options(target)["//command_line_option:platforms"]]), providers(target)["DefaultInfo"].files_to_run.executable.path)`,
	)
	if err != nil {
		t.Fatal(err)
	}
	for _, tool := range []string{":go-protoc", ":go_proto_reset_plugin_"} {
		foundOnPlatform := false
		for _, line := range strings.Split(strings.TrimSpace(string(cqueryOut)), "\n") {
			parts := strings.SplitN(line, "|", 3)
			if len(parts) != 3 || !strings.HasSuffix(parts[0], tool) {
				continue
			}
			label, platforms, executable := parts[0], normalizeLabel(parts[1]), parts[2]
			isInput := false
			for _, input := range inputs {
				if input == executable {
					isInput = true
					break
				}
			}
			switch {
			case platforms == platform:
				if !isInput {
					t.Errorf("%s configured for %s (%s) is not an input of GoProtocGen running on %s:\n%s", label, platforms, executable, platform, strings.Join(inputs, "\n"))
				}
				foundOnPlatform = true
			case isInput:
				t.Errorf("%s configured for %s (%s) is an input of GoProtocGen, but the action runs on %s", label, platforms, executable, platform)
			}
		}
		if !foundOnPlatform {
			t.Errorf("no instance of %s configured for %s found in:\n%s", tool, platform, cqueryOut)
		}
	}
}

// normalizeLabel removes the repository name prefix of canonical and
// non-canonical labels of the main repository.
func normalizeLabel(label string) string {
	return strings.TrimLeft(label, "@")
}
