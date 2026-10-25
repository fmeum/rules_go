//go:build unix

package lib

// The driver has to filter files by build constraints, otherwise type checking
// fails since greeting is declared twice.
func greeting() string {
	return "hello from unix"
}
