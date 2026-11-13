shader_type spatial;
// Scannerpulsen: en kugle, der kun lyser i kanten (fresnel), så man ser en
// bølge brede sig ud, ikke en farvet tåge.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform float fade = 1.0;
uniform vec4 color : source_color = vec4(0.3, 1.0, 0.9, 1.0);

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(rim, 4.0);
	// Vandrette scanlinjer for retrofølelse
	float lines = 0.75 + 0.25 * step(0.5, fract(FRAGCOORD.y * 0.25));
	ALBEDO = color.rgb * lines;
	ALPHA = edge * fade * 0.9;
}
