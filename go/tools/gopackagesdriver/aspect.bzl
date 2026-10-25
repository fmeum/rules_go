# Copyright 2021 The Bazel Go Rules Authors. All rights reserved.
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
    "//go/private:providers.bzl",
    "GoArchive",
    "GoStdLib",
)
load(
    "//go/tools/gopackagesdriver/pkgjson:pkg_json.bzl",
    "write_pkg_json",
    file_path_lib = "file_path",
    is_file_external_lib = "is_file_external",
)

GoPkgInfo = provider(
    doc = """Information needed to load a Go target with gopackagesdriver.

    driver_inputs and driver_env let a rule run a go/packages-based tool in an
    action of the same build: pass them as the action's inputs and env and
    query the target by its import path. They are empty for targets that don't
    provide GoArchive.
    """,
)

DEPS_ATTRS = [
    "deps",
    "embed",
]

PROTO_COMPILER_ATTRS = [
    "compiler",
    "compilers",
    "library",
]

def is_file_external(f):
    return is_file_external_lib(f)

def file_path(f):
    return file_path_lib(f)

# make_pkg_json_with_archive generates a pkg.json file from an archive
# and supports cgo generated code.
#
# This function was created to avoid breaking the signature of make_pkg_json
# and avoid adding an explicit field for cgo output files in the pkg.json.
def make_pkg_json_with_archive(ctx, name, archive):
    pkg_json_file = ctx.actions.declare_file(name + ".pkg.json")
    write_pkg_json(ctx, ctx.executable._pkgjson, archive, pkg_json_file)
    return pkg_json_file

# deprecated: use make_pkg_json_with_archive instead
def make_pkg_json(ctx, name, pkg_info):
    pkg_json_file = ctx.actions.declare_file(name + ".pkg.json")
    ctx.actions.write(pkg_json_file, content = json.encode(pkg_info))
    return pkg_json_file

def _write_pkg_json_list(ctx, pkg_json_files, stdlib_json_file):
    pkg_json_list = ctx.actions.declare_file(ctx.label.name + ".pkg_json_list")
    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add_all(pkg_json_files)
    args.add(stdlib_json_file)
    ctx.actions.write(pkg_json_list, args)
    return pkg_json_list

def _go_pkg_info_aspect_impl(target, ctx):
    # Fetch the stdlib JSON file from the inner most target
    stdlib_json_file = None
    stdlib_cache_dir = None
    stdlib_srcs = None

    transitive_json_files = []
    transitive_export_files = []
    transitive_compiled_go_files = []

    for attr in DEPS_ATTRS + PROTO_COMPILER_ATTRS:
        deps = getattr(ctx.rule.attr, attr, []) or []

        # Some attrs are not iterable, ensure that deps is always iterable.
        if type(deps) != type([]):
            deps = [deps]

        for dep in deps:
            if GoPkgInfo in dep:
                pkg_info = dep[GoPkgInfo]
                transitive_json_files.append(pkg_info.pkg_json_files)
                transitive_compiled_go_files.append(pkg_info.compiled_go_files)
                transitive_export_files.append(pkg_info.export_files)

                # Fetch the stdlib json from the first dependency
                if not stdlib_json_file:
                    stdlib_json_file = pkg_info.stdlib_json_file
                    stdlib_cache_dir = pkg_info.stdlib_cache_dir
                    stdlib_srcs = pkg_info.stdlib_srcs

    pkg_json_files = []
    compiled_go_files = []
    export_files = []

    if GoArchive in target:
        archive = target[GoArchive]
        compiled_go_files.extend(archive.source.srcs)
        if archive.data.cgo_out_dir:
            compiled_go_files.append(archive.data.cgo_out_dir)
        export_files.append(archive.data.export_file)
        pkg_json_files.append(make_pkg_json_with_archive(ctx, archive.data.name, archive))

        if ctx.rule.kind == "go_test":
            for dep_archive in archive.direct:
                # find the archive containing the test sources
                if archive.data.label == dep_archive.data.label:
                    pkg_json_files.append(make_pkg_json_with_archive(ctx, dep_archive.data.name, dep_archive))
                    compiled_go_files.extend(dep_archive.source.srcs)
                    if dep_archive.data.cgo_out_dir:
                        compiled_go_files.append(dep_archive.data.cgo_out_dir)
                    export_files.append(dep_archive.data.export_file)
                    break

    # If there was no stdlib json in any dependencies, fetch it from the
    # current go_ node.
    if not stdlib_json_file:
        stdlib = ctx.attr._go_stdlib[GoStdLib]
        stdlib_json_file = stdlib._list_json
        stdlib_cache_dir = stdlib.cache_dir
        stdlib_srcs = stdlib._srcs

    pkg_json_files = depset(
        direct = pkg_json_files,
        transitive = transitive_json_files,
    )
    compiled_go_files = depset(
        direct = compiled_go_files,
        transitive = transitive_compiled_go_files,
    )
    export_files = depset(
        direct = export_files,
        transitive = transitive_export_files,
    )

    driver_inputs = depset()
    driver_env = {}
    if GoArchive in target:
        pkg_json_list = _write_pkg_json_list(ctx, pkg_json_files, stdlib_json_file)
        driver = ctx.executable._gopackagesdriver
        driver_inputs = depset(
            direct = [pkg_json_list, stdlib_json_file, driver],
            transitive = [
                pkg_json_files,
                compiled_go_files,
                export_files,
                stdlib_cache_dir or depset(),
                # Needed to type-check the standard library from source,
                # which go/packages does unless export_stdlib is set.
                stdlib_srcs,
            ],
        )
        mode = target[GoArchive].source.mode
        driver_env = {
            "GOPACKAGESDRIVER": driver.path,
            "GOPACKAGESDRIVER_PKG_JSON_LIST": pkg_json_list.path,
            # The driver filters source files for the target platform and tags.
            "GOOS": mode.goos,
            "GOARCH": mode.goarch,
            "GOTAGS": ",".join(mode.tags),
            "CGO_ENABLED": "0" if mode.pure else "1",
        }

    pkg_info = GoPkgInfo(
        stdlib_json_file = stdlib_json_file,
        stdlib_cache_dir = stdlib_cache_dir,
        stdlib_srcs = stdlib_srcs,
        pkg_json_files = pkg_json_files,
        compiled_go_files = compiled_go_files,
        export_files = export_files,
        driver_inputs = driver_inputs,
        driver_env = driver_env,
    )

    return [
        pkg_info,
        OutputGroupInfo(
            go_pkg_driver_json_file = pkg_info.pkg_json_files,
            go_pkg_driver_srcs = pkg_info.compiled_go_files,
            go_pkg_driver_export_file = pkg_info.export_files,
            go_pkg_driver_stdlib_json_file = depset([pkg_info.stdlib_json_file] if pkg_info.stdlib_json_file else []),
            go_pkg_driver_stdlib_cache_dir = pkg_info.stdlib_cache_dir or depset([]),
        ),
    ]

go_pkg_info_aspect = aspect(
    implementation = _go_pkg_info_aspect_impl,
    attr_aspects = DEPS_ATTRS + PROTO_COMPILER_ATTRS,
    attrs = {
        "_go_stdlib": attr.label(
            default = "//:stdlib",
        ),
        "_gopackagesdriver": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//go/tools/gopackagesdriver:reset_gopackagesdriver"),
        ),
        "_pkgjson": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//go/tools/gopackagesdriver/pkgjson:reset_pkgjson"),
        ),
    },
)
