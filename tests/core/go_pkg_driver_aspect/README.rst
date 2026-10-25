go_pkg_driver_aspect
====================

.. _go_pkg_driver_aspect: /go/tools/gopackagesdriver/aspect.bzl

Tests that a rule can run a go/packages-based tool in an action, using the
inputs and environment that `go_pkg_driver_aspect`_ provides.

lib_report_test
---------------

`go_packages_report` (in `defs.bzl`) applies `go_pkg_driver_aspect`_ to `:lib`
and runs `:report` in a sandboxed action that loads `example.com/lib` through
gopackagesdriver. Checks that the types of the target, its dependency (loaded
from export data) and the standard library (loaded from source) resolve, and
that files are filtered by build constraints.

stringer/color_test
-------------------

A complete example of a code generator built on go/packages. `go_stringer` (in
`stringer/defs.bzl`) applies `go_pkg_driver_aspect`_ to `:color_decls` and runs
`:stringer` in an action that loads the package and generates a `String`
method for `Color`, similar to `golang.org/x/tools/cmd/stringer`. `:color`
compiles the generated file together with the declarations and `color_test`
checks the generated method. The generator needs the syntax and types of the
package as well as constants declared in a dependency and in the standard
library.
