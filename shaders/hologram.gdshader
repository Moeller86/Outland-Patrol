shader_type spatial;
// Hologram til målskærmen i cockpittet: ensfarvet, lysere kanter og scanlinjer.
render_mode unshaded, cull_back;

uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.11, 1.0);

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float lines = step(0.5, fract(FRAGCOORD.y * 0.5));
	vec3 c = tint.rgb * (0.25 + 0.55 * rim + 0.35 * lines);
	// Lidt lysere flader, der vender opad, så formen kan ses
	c += tint.rgb * 0.25 * clamp(dot(NORMAL, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	ALBEDO = c;
}
