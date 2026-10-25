load("@io_bazel_rules_go//go:def.bzl", "GoArchive")
load("@io_bazel_rules_go//go/tools/gopackagesdriver:aspect.bzl", "GoPkgDriverInfo", "go_pkg_driver_aspect")

def _go_stringer_impl(ctx):
    driver_info = ctx.attr.dep[GoPkgDriverInfo]

    args = ctx.actions.args()
    args.add("-type", ctx.attr.type)
    args.add("-output", ctx.outputs.out)
    if ctx.attr.linecomment:
        args.add("-linecomment")
    args.add(ctx.attr.dep[GoArchive].data.importpath)

    ctx.actions.run(
        executable = ctx.executable._stringer,
        arguments = [args],
        inputs = driver_info.inputs,
        env = driver_info.env,
        outputs = [ctx.outputs.out],
        mnemonic = "GoStringer",
        progress_message = "Generating String method for %{label}",
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

go_stringer = rule(
    implementation = _go_stringer_impl,
    attrs = {
        "dep": attr.label(
            mandatory = True,
            providers = [GoArchive],
            aspects = [go_pkg_driver_aspect],
            doc = "The Go library that declares the type and its constants.",
        ),
        "linecomment": attr.bool(
            doc = "Use the line comment of a constant as its name.",
        ),
        "out": attr.output(
            mandatory = True,
            doc = "The Go file to generate.",
        ),
        "type": attr.string(
            mandatory = True,
            doc = "The name of the type to generate a String method for.",
        ),
        "_stringer": attr.label(
            default = ":stringer",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Generates a String method for an integer type, like golang.org/x/tools/cmd/stringer.",
)
