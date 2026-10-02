shader_type canvas_item;

void fragment() {
	vec4 glyph = texture(TEXTURE, UV) * COLOR;
	// Keep the two people from DE; the surrounding well is square.
	glyph.a *= 1.0 - step(0.42, distance(UV, vec2(0.5)));
	COLOR = glyph;
}
