package color

import "testing"

func TestString(t *testing.T) {
	for _, tc := range []struct {
		color Color
		want  string
	}{
		{Red, "Red"},
		{Green, "green"},
		{Blue, "Blue"},
		{Crimson, "Red"},
		{Infrared, "Infrared"},
		{Ultraviolet, "Ultraviolet"},
		{Max, "Max"},
		{notAColor, "Color(7)"},
		{Color(42), "Color(42)"},
	} {
		if got := tc.color.String(); got != tc.want {
			t.Errorf("Color(%d).String() = %q, want %q", int(tc.color), got, tc.want)
		}
	}
}
