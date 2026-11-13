// Planetoverflade med vertexfarver. Kan skære et "hul" omkring et punkt, så
// det detaljerede terræn tæt på jorden kan tegnes i stedet uden at overlappe.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 hole_center = vec3(0.0);
uniform float hole_radius = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (hole_radius > 0.0 && distance(world_pos, hole_center) < hole_radius) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
