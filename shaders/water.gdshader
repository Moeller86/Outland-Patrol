shader_type spatial;
// Vand i pixelstil: striber, der flyder. flow = 0 for søer (langsom bølgen),
// flow = 1 for vandfald (hurtigt fald nedad langs modellens lokale y).
render_mode unshaded, cull_disabled;

uniform float flow = 0.0;
uniform vec4 deep : source_color = vec4(0.12, 0.45, 0.85, 1.0);
uniform vec4 light : source_color = vec4(0.62, 0.9, 1.0, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.98, 1.0, 1.0);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = TIME;
	float v;
	if (flow > 0.5) {
		// Vandfald: lodrette striber, der falder
		float col = floor(lp.x * 0.8);
		float speed = 18.0 + fract(sin(col * 12.9898) * 43758.5) * 10.0;
		v = fract((lp.y + t * speed) * 0.08 + fract(sin(col * 78.233) * 43758.5));
	} else {
		v = fract((lp.x + lp.z) * 0.05 + sin(lp.x * 0.1 + t) * 0.3 + t * 0.15);
	}
	vec3 c = mix(deep.rgb, light.rgb, step(0.55, v));
	c = mix(c, foam.rgb, step(0.9, v));
	ALBEDO = c;
}
