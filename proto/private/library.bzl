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
    "@bazel_skylib//lib:types.bzl",
    "types",
)
load(
    "@com_google_protobuf//bazel/common:proto_info.bzl",
    "ProtoInfo",
)
load(
    "//go:def.bzl",
    "GoInfo",
    "go_context",
    "go_rule",
)
load(
    "//go/private:common.bzl",
    "GO_TOOLCHAIN",
)
load(
    "//go/private:context.bzl",
    "CGO_ATTRS",
    "CGO_FRAGMENTS",
    "CGO_TOOLCHAINS",
    "new_go_info",
    rule_maybe_needs_cc_toolchain = "maybe_needs_cc_toolchain",
)
load(
    "//go/private/rules:transition.bzl",
    "non_go_tool_transition",
)
load(
    "//proto:compiler.bzl",
    "GO_PROTO_GEN_EXEC_GROUP",
    "GoProtoCompiler",
    "find_proto_toolchain",
    "go_proto_gen_attrs",
    "go_proto_gen_exec_groups",
    "proto_path",
)

GoProtoImports = provider()

def get_imports(attr, importpath):
    # ctx.attr.proto is a one-element array since there is a Starlark transition attached to it.
    if hasattr(attr, "proto") and attr.proto and types.is_list(attr.proto) and ProtoInfo in attr.proto[0]:
        proto_deps = [attr.proto[0]]
    elif hasattr(attr, "protos"):
        proto_deps = [d for d in attr.protos if ProtoInfo in d]
    else:
        proto_deps = []

    direct = dict()
    for dep in proto_deps:
        for src in dep[ProtoInfo].check_deps_sources.to_list():
            direct["{}={}".format(proto_path(src, dep[ProtoInfo]), importpath)] = True

    deps = getattr(attr, "deps", []) + getattr(attr, "embed", [])
    transitive = [
        dep[GoProtoImports].imports
        for dep in deps
        if GoProtoImports in dep
    ]
    return depset(direct = direct.keys(), transitive = transitive)

def _go_proto_aspect_impl(_target, ctx):
    attr = ctx.rule.attr
    for attr_name in ["importpath", "_go_context_data"]:
        if not hasattr(attr, attr_name):
            fail("""While processing go_proto_library deps: {label}, which is a {kind} is missing the '{attr_name}' \
attribute. go_proto_library deps are usually other go_proto_library targets. We recommend double-checking the deps \
to make sure they're the right type. If this is intentional (for example you're developing a new rule) make sure it \
declares the \"{attr_name}\" attribute.""".format(
                label = _target.label,
                kind = ctx.rule.kind,
                attr_name = attr_name,
            ))

    go = go_context(
        ctx,
        attr,
        importpath = attr.importpath,
        go_context_data = attr._go_context_data,
        maybe_needs_cc_toolchain = False,
    )
    imports = get_imports(attr, go.importpath)
    return [GoProtoImports(imports = imports)]

_go_proto_aspect = aspect(
    _go_proto_aspect_impl,
    attr_aspects = [
        "deps",
        "embed",
    ],
    attrs = CGO_ATTRS,
    fragments = CGO_FRAGMENTS,
    toolchains = [GO_TOOLCHAIN] + CGO_TOOLCHAINS,
)

def _proto_library_to_source(_go, attr, source, merge):
    if attr.compiler:
        compilers = [attr.compiler]
    else:
        compilers = attr.compilers
    for compiler in compilers:
        if GoInfo in compiler:
            merge(source, compiler[GoInfo])

def _go_proto_library_maybe_needs_cc_toolchain(ctx):
    compilers = [ctx.attr.compiler] if ctx.attr.compiler else ctx.attr.compilers
    return rule_maybe_needs_cc_toolchain(ctx.attr, go_infos = compilers)

def _go_proto_library_impl(ctx):
    go = go_context(
        ctx,
        importpath = ctx.attr.importpath,
        importmap = ctx.attr.importmap,
        importpath_aliases = ctx.attr.importpath_aliases,
        embed = ctx.attr.embed,
        go_context_data = ctx.attr._go_context_data,
        maybe_needs_cc_toolchain = _go_proto_library_maybe_needs_cc_toolchain(ctx),
    )
    if ctx.attr.compiler:
        #TODO: print("DEPRECATED: compiler attribute on {}, use compilers instead".format(ctx.label))
        compilers = [ctx.attr.compiler]
    else:
        compilers = ctx.attr.compilers

    # The same compilers, but configured for the execution platform of the
    # GoProtocGen actions so that their tools can be run by these actions. The
    # go_proto_library macro sets this attribute to the value of compiler(s).
    tool_compilers = ctx.attr.internal_use_only_compiler_tools
    if [t.label for t in tool_compilers] != [c.label for c in compilers]:
        fail("internal_use_only_compiler_tools must match compiler(s). Use the go_proto_library macro from @io_bazel_rules_go//proto:def.bzl rather than the underlying rule.")
    proto_toolchain = find_proto_toolchain(ctx)

    if ctx.attr.proto:
        #TODO: print("DEPRECATED: proto attribute on {}, use protos instead".format(ctx.label))
        if ctx.attr.protos:
            fail("Either proto or protos (non-empty) argument must be specified, but not both")

        # ctx.attr.proto is a one-element array since there is a Starlark transition attached to it.
        proto_deps = [ctx.attr.proto[0]]
    else:
        if not ctx.attr.protos:
            fail("Either proto or protos (non-empty) argument must be specified")
        proto_deps = ctx.attr.protos

    go_srcs = []
    valid_archive = False

    for c, t in zip(compilers, tool_compilers):
        compiler = c[GoProtoCompiler]
        if compiler.valid_archive:
            valid_archive = True

        # Only the tools of the exec-configured compiler are used, deps and
        # GoInfo come from the compiler in the target configuration.
        tools = t[GoProtoCompiler]
        go_srcs.extend(tools.compile(
            go,
            compiler = tools,
            protos = [d[ProtoInfo] for d in proto_deps],
            imports = get_imports(ctx.attr, go.importpath),
            importpath = go.importpath,
            proto_toolchain = proto_toolchain,
        ))

    go_info = new_go_info(
        go,
        ctx.attr,
        resolver = _proto_library_to_source,
        generated_srcs = go_srcs,
        coverage_instrumented = False,
    )
    providers = [go_info]
    output_groups = {
        "go_generated_srcs": go_srcs,
    }
    if valid_archive:
        archive = go.archive(go, go_info)
        output_groups["compilation_outputs"] = [archive.data.file]
        providers.extend([
            archive,
            DefaultInfo(
                files = depset([archive.data.file]),
                runfiles = archive.runfiles,
            ),
        ])
    return providers + [OutputGroupInfo(**output_groups)]

go_proto_library = go_rule(
    implementation = _go_proto_library_impl,
    attrs = {
        "proto": attr.label(
            cfg = non_go_tool_transition,
            providers = [ProtoInfo],
        ),
        "protos": attr.label_list(
            cfg = non_go_tool_transition,
            providers = [ProtoInfo],
            default = [],
        ),
        "deps": attr.label_list(
            providers = [GoInfo],
            aspects = [_go_proto_aspect],
        ),
        "importpath": attr.string(),
        "importmap": attr.string(),
        "importpath_aliases": attr.string_list(),  # experimental, undocumented
        "embed": attr.label_list(providers = [GoInfo]),
        "gc_goopts": attr.string_list(),
        "compiler": attr.label(providers = [GoProtoCompiler]),
        "compilers": attr.label_list(
            providers = [GoProtoCompiler],
            default = ["//proto:go_proto"],
        ),
        "internal_use_only_compiler_tools": attr.label_list(
            providers = [GoProtoCompiler],
            cfg = config.exec(GO_PROTO_GEN_EXEC_GROUP),
            doc = """Set by the go_proto_library macro to the same value as
            compiler(s). The compilers are configured for the execution
            platform of the GoProtocGen actions, which is the only way to
            guarantee that the tools they provide can run there.""",
        ),
        "_go_context_data": attr.label(
            default = "//:go_context_data",
        ),
        "_nogo": attr.label(
            default = Label("@io_bazel_rules_nogo//:nogo"),
            cfg = "exec",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | go_proto_gen_attrs(),
    # GoProtocGen actions run in a dedicated exec group that is independent of
    # the rule's own toolchain requirements (in particular the Go toolchain,
    # which may only be registered for the host). All tools used by these
    # actions are configured for this exec group's execution platform, see
    # GO_PROTO_GEN_EXEC_GROUP in compiler.bzl.
    exec_groups = go_proto_gen_exec_groups(),
)
