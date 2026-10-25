package color

import (
	"math"

	"example.com/palette"
)

type Color int

const (
	Red   Color = iota
	Green       // green
	Blue

	// Crimson has the same value as Red, so its String method returns "Red".
	Crimson = Red

	// go/packages evaluates these constants with type information from a
	// dependency, which it loads from export data, and from the standard
	// library, which it type-checks from source.
	Infrared    Color = palette.Infrared
	Ultraviolet Color = palette.Ultraviolet
	Max         Color = math.MaxInt32
)

// notAColor has another type, so it doesn't affect the String method.
const notAColor = 7
