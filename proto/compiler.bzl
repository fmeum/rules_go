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
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load("@com_google_protobuf//bazel/common:proto_common.bzl", "proto_common")
load(
    "@com_google_protobuf//bazel/common:proto_lang_toolchain_info.bzl",
    "ProtoLangToolchainInfo",
)
load(
    "//go:def.bzl",
    "GoInfo",
    "go_context",
    "go_rule",
)
load(
    "//go/private:context.bzl",
    "new_go_info",
)
load(
    "//go/private/rules:transition.bzl",
    "go_reset_target",
)

# This is actually a misuse of Proto toolchains: The proper way to use `protoc` would be to go
# through a Go-specific `proto_lang_toolchain` and use the methods on `proto_common` to interact
# with `protoc`. Since rules_go has a very bespoke setup with customizable compilers and the need
# to apply reset transitions in case `protoc` *is* built from source, this would require major
# changes.
# TODO: Revisit this after --incompatible_enable_proto_toolchain_resolution has been enabled by
#  default.
_PROTO_TOOLCHAIN_TYPE = "@rules_proto//proto:toolchain_type"

def _incompatible_toolchains_enabled():
    return getattr(proto_common, "INCOMPATIBLE_ENABLE_PROTO_TOOLCHAIN_RESOLUTION", False)

def _use_toolchain(toolchain_type):
    if _incompatible_toolchains_enabled():
        return [config_common.toolchain_type(toolchain_type, mandatory = False)]
    else:
        return []

def _if_legacy_toolchain(legacy_attr_dict):
    if _incompatible_toolchains_enabled():
        return {}
    else:
        return legacy_attr_dict

# The exec group in which go_proto_library runs its GoProtocGen actions.
#
# Every tool these actions execute has to be built for the execution platform
# resolved for this exec group, otherwise the action may e.g. attempt to run a
# host binary on a remote worker ("Exec format error"). This is guaranteed by
# construction rather than by matching independent toolchain resolutions:
#
# * protoc comes from the proto toolchain resolved for this exec group (with
#   --incompatible_enable_proto_toolchain_resolution) or from an attribute with
#   cfg = config.exec(GO_PROTO_GEN_EXEC_GROUP) (without it). Toolchains
#   resolved for an exec group build their tools for its execution platform.
# * go-protoc and the plugin are ordinary (untransitioned) dependencies of
#   go_proto_compiler. go_proto_library depends on its compilers with
#   cfg = config.exec(GO_PROTO_GEN_EXEC_GROUP) to obtain these tools, so they
#   are built for exactly the platform the action runs on.
#
# The exec group intentionally does not require the Go toolchain: the Go tools
# are cross-compiled for its execution platform by their own toolchain
# resolution and do not need a Go SDK at runtime. Requiring it would restrict
# the action to platforms with a registered Go SDK for no benefit.
GO_PROTO_GEN_EXEC_GROUP = "internal_use_only_go_proto_gen"

def go_proto_gen_exec_groups():
    """Returns the exec_groups a rule needs to call go_proto_compile."""
    return {
        GO_PROTO_GEN_EXEC_GROUP: exec_group(
            toolchains = _use_toolchain(_PROTO_TOOLCHAIN_TYPE),
        ),
    }

def go_proto_gen_attrs():
    """Returns the attributes a rule needs to call find_proto_toolchain."""
    return _if_legacy_toolchain({
        "_legacy_proto_toolchain": attr.label(
            # Setting cfg = config.exec(...) here as the legacy_proto_toolchain
            # target already needs to apply the non_go_tool_transition.
            # Flipping the two would be more idiomatic, but
            # proto_toolchains.find_toolchain doesn't support split transitions.
            cfg = config.exec(GO_PROTO_GEN_EXEC_GROUP),
            default = "//proto/private:legacy_proto_toolchain",
        ),
    })

def find_proto_toolchain(ctx):
    """Returns the ProtoLangToolchainInfo providing protoc for GoProtocGen actions.

    The rule must declare go_proto_gen_exec_groups() and go_proto_gen_attrs().
    """
    if _incompatible_toolchains_enabled():
        toolchain = ctx.exec_groups[GO_PROTO_GEN_EXEC_GROUP].toolchains[_PROTO_TOOLCHAIN_TYPE]
        if not toolchain:
            fail("No toolchains registered for '%s'." % _PROTO_TOOLCHAIN_TYPE)
        return toolchain.proto
    else:
        return ctx.attr._legacy_proto_toolchain[ProtoLangToolchainInfo]

GoProtoCompiler = provider(
    doc = "Information and dependencies needed to generate Go code from protos",
    fields = {
        "compile": """A function with the signature:

    def compile(go, compiler, protos, imports, importpath, proto_toolchain)

where go is the go_context object, compiler is this GoProtoCompiler, protos
is a list of ProtoInfo providers for protos to compile, imports is a depset
of strings mapping proto import paths to Go import paths, importpath is
the import path of the Go library being generated and proto_toolchain is the
ProtoLangToolchainInfo providing protoc for the GO_PROTO_GEN_EXEC_GROUP exec
group.

The function should declare output .go files and actions to generate them.
Actions must run in the GO_PROTO_GEN_EXEC_GROUP exec group; the compiler
passed to this function has been configured for that exec group's execution
platform, so its tools can be executed by such actions.
It should return a list of .go Files to be compiled by the Go compiler.
""",
        "deps": """List of targets providing GoInfo and GoArchive.
These are added as implicit dependencies for any go_proto_library using this
compiler. Typically, these are Well Known Types and proto runtime libraries.""",
        "valid_archive": """A Boolean indicating whether the .go files produced
by this compiler are buildable on their own. Compilers that just add methods
to structs produced by other compilers will set this to False.""",
        "always_generates": """A Boolean indicating whether this compiler
        always generates files, regardless of whether the proto files have
        relevant definitions (e.g., services for grpc_gateway). This allows
        more strict check of compiler output.""",
        "internal": "Opaque value containing data used by compile.",
    },
)

def go_proto_compile(go, compiler, protos, imports, importpath, proto_toolchain):
    """Invokes protoc to generate Go sources for a given set of protos

    Args:
        go: the go object, returned by go_context.
        compiler: a GoProtoCompiler provider, configured for the execution
            platform of the GO_PROTO_GEN_EXEC_GROUP exec group.
        protos: list of ProtoInfo providers for protos to compile.
        imports: depset of strings mapping proto import paths to Go import paths.
        importpath: the import path of the Go library being generated.
        proto_toolchain: the ProtoLangToolchainInfo returned by
            find_proto_toolchain, providing protoc for the same exec group.

    Returns:
        A list of .go Files generated by the compiler.
    """

    go_srcs = []
    outpath = None
    proto_paths = {}
    desc_sets = []
    for proto in protos:
        desc_sets.append(proto.transitive_descriptor_sets)
        for src in proto.check_deps_sources.to_list():
            path = proto_path(src, proto)
            if path in proto_paths:
                if proto_paths[path] != src:
                    fail("proto files {} and {} have the same import path, {}".format(
                        src.path,
                        proto_paths[path].path,
                        path,
                    ))
                continue
            proto_paths[path] = src

            suffixes = compiler.internal.suffixes
            if not suffixes:
                suffixes = [compiler.internal.suffix]
            for suffix in suffixes:
                out = go.declare_file(
                    go,
                    path = importpath + "/" + src.basename[:-len(".proto")],
                    ext = suffix,
                )
                go_srcs.append(out)
            if outpath == None:
                outpath = go_srcs[0].dirname[:-len(importpath)]

    transitive_descriptor_sets = depset(direct = [], transitive = desc_sets)

    args = go.actions.args()
    args.add("-protoc", proto_toolchain.proto_compiler.executable)
    args.add("-importpath", importpath)
    args.add("-out_path", outpath)
    args.add("-plugin", compiler.internal.plugin.executable)
    if compiler.always_generates:
        args.add("-strict")

    # TODO(jayconrod): can we just use go.env instead?
    args.add_all(compiler.internal.options, before_each = "-option")
    if compiler.internal.import_path_option:
        args.add_all([importpath], before_each = "-option", format_each = "import_path=%s")
    args.add_all(transitive_descriptor_sets, before_each = "-descriptor_set")
    args.add_all(go_srcs, before_each = "-expected")
    args.add_all(imports, before_each = "-import")
    args.add_all(proto_paths.keys())
    args.use_param_file("-param=%s")
    go.actions.run(
        inputs = depset(
            direct = [
                compiler.internal.go_protoc,
            ],
            transitive = [transitive_descriptor_sets],
        ),
        outputs = go_srcs,
        progress_message = "Generating into %s" % go_srcs[0].dirname,
        mnemonic = "GoProtocGen",
        executable = compiler.internal.go_protoc,
        exec_group = GO_PROTO_GEN_EXEC_GROUP,
        tools = [proto_toolchain.proto_compiler, compiler.internal.plugin],
        arguments = [args],
        env = go.env,
        # We may need the shell environment (potentially augmented with --action_env)
        # to invoke protoc on Windows. If protoc was built with mingw, it probably needs
        # .dll files in non-default locations that must be in PATH. The target configuration
        # may not have a C compiler, so we have no idea what PATH should be.
        use_default_shell_env = "PATH" not in go.env,
    )
    return go_srcs

def proto_path(src, proto):
    """proto_path returns the string used to import the proto. This is the proto
    source path within its repository, adjusted by import_prefix and
    strip_import_prefix.

    Args:
        src: the proto source File.
        proto: the ProtoInfo provider.

    Returns:
        An import path string.
    """
    if proto.proto_source_root == ".":
        # true if proto sources were generated
        prefix = src.root.path + "/"
    elif proto.proto_source_root.startswith(src.root.path):
        # sometimes true when import paths are adjusted with import_prefix
        prefix = proto.proto_source_root + "/"
    else:
        # usually true when paths are not adjusted
        prefix = paths.join(src.root.path, proto.proto_source_root) + "/"
    if not src.path.startswith(prefix):
        # sometimes true when importing multiple adjusted protos
        return src.path
    return src.path[len(prefix):]

def _go_proto_compiler_impl(ctx):
    go = go_context(
        ctx,
        maybe_needs_cc_toolchain = False,
    )
    go_info = new_go_info(go, ctx.attr)
    return [
        GoProtoCompiler(
            deps = ctx.attr.deps,
            compile = go_proto_compile,
            valid_archive = ctx.attr.valid_archive,
            always_generates = ctx.attr.always_generates,
            internal = struct(
                options = ctx.attr.options,
                suffix = ctx.attr.suffix,
                suffixes = ctx.attr.suffixes,
                go_protoc = ctx.executable._go_protoc,
                plugin = ctx.attr.plugin[DefaultInfo].files_to_run,
                import_path_option = ctx.attr.import_path_option,
            ),
        ),
        go_info,
    ]

_go_proto_compiler = go_rule(
    implementation = _go_proto_compiler_impl,
    attrs = {
        "deps": attr.label_list(providers = [GoInfo]),
        "options": attr.string_list(),
        "suffix": attr.string(default = ".pb.go"),
        "suffixes": attr.string_list(),
        "valid_archive": attr.bool(default = True),
        "always_generates": attr.bool(
            default = False,
            doc = "indicates whether this proto compiler always generate files, regardless of whether the proto files have relevant definitions (e.g., services for grpc_gateway).",
        ),
        "import_path_option": attr.bool(default = False),
        # The tools are deliberately not built with cfg = "exec": that would
        # resolve an execution platform for this target, which is unrelated to
        # the one go_proto_library's GoProtocGen actions run on. Instead,
        # go_proto_library depends on this target with
        # cfg = config.exec(GO_PROTO_GEN_EXEC_GROUP), so that the tools are
        # configured for the execution platform of the actions that run them.
        "plugin": attr.label(
            executable = True,
            cfg = "target",
            mandatory = True,
        ),
        "_go_protoc": attr.label(
            executable = True,
            cfg = "target",
            default = "//go/tools/builders:go-protoc",
        ),
        "_go_context_data": attr.label(
            default = "//:go_context_data",
        ),
    },
)

def go_proto_compiler(name, **kwargs):
    plugin = kwargs.pop("plugin", "@com_github_golang_protobuf//protoc-gen-go")
    reset_plugin_name = name + "_reset_plugin_"
    go_reset_target(
        name = reset_plugin_name,
        dep = plugin,
        visibility = ["//visibility:private"],
    )
    _go_proto_compiler(
        name = name,
        plugin = reset_plugin_name,
        **kwargs
    )
