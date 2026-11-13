shader_type spatial;
// Finmasket terræn under skibet: flade trekanter i pixelstil fra en indekseret maske.
// Normalen regnes ud fra skærmafledte (én pr. trekant), og farven tages fra
// trekantens første hjørne (flat), så hver trekant får én farve.
render_mode specular_disabled, cull_back;

varying flat vec3 col;

void vertex() {
	col = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
