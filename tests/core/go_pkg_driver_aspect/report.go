// report loads Go packages with go/packages and writes the exported API of
// each root package.
package main

import (
	"flag"
	"fmt"
	"go/types"
	"log"
	"os"
	"strings"

	"golang.org/x/tools/go/packages"
)

func main() {
	out := flag.String("out", "", "path to write the report to")
	flag.Parse()

	cfg := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedTypes | packages.NeedTypesSizes |
			packages.NeedSyntax | packages.NeedTypesInfo,
	}
	pkgs, err := packages.Load(cfg, flag.Args()...)
	if err != nil {
		log.Fatal(err)
	}
	if packages.PrintErrors(pkgs) > 0 {
		os.Exit(1)
	}

	var b strings.Builder
	for _, pkg := range pkgs {
		fmt.Fprintln(&b, pkg.PkgPath)
		scope := pkg.Types.Scope()
		for _, name := range scope.Names() {
			if obj := scope.Lookup(name); obj.Exported() {
				fmt.Fprintf(&b, "\t%s\n", types.ObjectString(obj, nil))
			}
		}
	}
	if err := os.WriteFile(*out, []byte(b.String()), 0o666); err != nil {
		log.Fatal(err)
	}
}
