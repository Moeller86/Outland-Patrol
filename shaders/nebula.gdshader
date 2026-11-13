// Tågebaggrund på en indvendig kugle. Blandes mod himmelfarven i atmosfæren.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D nebula : source_color, filter_nearest, repeat_enable;
uniform vec3 sky_color : source_color = vec3(0.5, 0.8, 1.0);
uniform float atmosphere : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = mix(texture(nebula, UV).rgb, sky_color, atmosphere);
}
