package lib

import (
	"bytes"

	"example.com/dep"
)

// Greeting refers to a type from a dependency, which go/packages loads from
// export data.
func Greeting() dep.Message {
	return dep.Message(greeting())
}

// NewBuffer refers to a type from the standard library, which go/packages
// type-checks from source unless export_stdlib is set.
func NewBuffer() *bytes.Buffer {
	return new(bytes.Buffer)
}
