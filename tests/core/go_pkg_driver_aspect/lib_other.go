//go:build !unix

package lib

func greeting() string {
	return "hello"
}
