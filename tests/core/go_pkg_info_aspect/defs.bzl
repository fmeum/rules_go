load("@io_bazel_rules_go//go:def.bzl", "GoArchive")
load("@io_bazel_rules_go//go/tools/gopackagesdriver:aspect.bzl", "GoPkgInfo", "go_pkg_info_aspect")

def _go_packages_report_impl(ctx):
    pkg_info = ctx.attr.dep[GoPkgInfo]
    out = ctx.actions.declare_file(ctx.label.name + ".txt")

    args = ctx.actions.args()
    args.add("-out", out)
    args.add(ctx.attr.dep[GoArchive].data.importpath)

    # The aspect provides everything the go/packages tool needs to load the
    # target through gopackagesdriver without invoking Bazel.
    ctx.actions.run(
        executable = ctx.executable._report,
        arguments = [args],
        inputs = pkg_info.driver_inputs,
        env = pkg_info.driver_env,
        outputs = [out],
        mnemonic = "GoPackagesReport",
    )
    return [DefaultInfo(files = depset([out]))]

go_packages_report = rule(
    implementation = _go_packages_report_impl,
    attrs = {
        "dep": attr.label(
            mandatory = True,
            providers = [GoArchive],
            aspects = [go_pkg_info_aspect],
        ),
        "_report": attr.label(
            default = ":report",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Writes the exported API of a Go package as seen by go/packages.",
)
