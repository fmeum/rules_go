# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "//proto/private:library.bzl",
    _GoProtoImports = "GoProtoImports",
    _get_imports = "get_imports",
    _go_proto_library = "go_proto_library",
)

GoProtoImports = _GoProtoImports
get_imports = _get_imports

_DEFAULT_COMPILERS = [Label("//proto:go_proto")]

def go_proto_library(name, compiler = None, compilers = None, **kwargs):
    """go_proto_library is a rule that takes a proto_library (in the proto
    attribute) and produces a go library for it.

    See proto/core.rst for documentation of the arguments.

    Args:
        name: the name of the target.
        compiler: equivalent to compilers with a single label.
        compilers: list of rules producing GoProtoCompiler providers.
        **kwargs: all other arguments of the go_proto_library rule.
    """

    # The tools provided by the compilers must be built for the execution
    # platform of the actions that run them. The rule depends on the compilers
    # a second time with cfg = config.exec(...) for this purpose.
    if compiler:
        compiler_tools = [compiler]
    elif compilers != None:
        compiler_tools = compilers
    else:
        compiler_tools = _DEFAULT_COMPILERS
    _go_proto_library(
        name = name,
        compiler = compiler,
        compilers = compilers,
        internal_use_only_compiler_tools = compiler_tools,
        **kwargs
    )


def go_grpc_library(name, **kwargs):
    if "compilers" not in kwargs:
        kwargs["compilers"] = [
            Label("//proto:go_proto"),
            Label("//proto:go_grpc_v2"),
        ]
    go_proto_library(
        name = name,
        **kwargs
    )

def proto_register_toolchains():
    print("You no longer need to call proto_register_toolchains(), it does nothing")
