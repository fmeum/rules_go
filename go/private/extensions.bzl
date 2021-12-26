load(":sdk.bzl", "go_download_sdk")

go_download_sdk_tag = tag_class(attrs = {
    "name": attr.string(doc = "Base name for generated repositories"),
    "goos": attr.string(),
    "goarch": attr.string(),
    "sdks": attr.string_list_dict(),
    "urls": attr.string_list(default = ["https://dl.google.com/go/{}"]),
    "version": attr.string(doc = "Version of the Go SDK"),
    "strip_prefix": attr.string(default = "go"),
})

def _sdk_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for sdk in mod.tags.download_sdk:
            if sdk.name in registrations.keys():
                if sdk.version == registrations[sdk.name]:
                    continue
                fail("Multiple conflicting Go SDKs declared for name {} ({} and {})".format(
                    sdk.name,
                    sdk.version,
                    registrations[sdk.name],
                ))
            else:
                registrations[sdk.name] = sdk.version
    for name, version in registrations.items():
        go_download_sdk(
            name = name,
            version = sdk.version,
            register = False,
        )

go = module_extension(
    implementation = _sdk_extension,
    tag_classes = {
        "download_sdk": go_download_sdk_tag,
    },
)
