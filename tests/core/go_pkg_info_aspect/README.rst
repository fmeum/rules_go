go_pkg_info_aspect
==================

.. _go_pkg_info_aspect: /go/tools/gopackagesdriver/aspect.bzl

Tests that a rule can run a go/packages-based tool in an action, using the
inputs and environment that `go_pkg_info_aspect`_ provides.

lib_report_test
---------------

`go_packages_report` (in `defs.bzl`) applies `go_pkg_info_aspect`_ to `:lib`
and runs `:report` in a sandboxed action that loads `example.com/lib` through
gopackagesdriver. Checks that the types of the target, its dependency (loaded
from export data) and the standard library (loaded from source) resolve, and
that files are filtered by build constraints.
