// Pixel-pipeline: verden renderes i lav opløsning i en SubViewport,
// og denne shader giver den begrænsede palette med ordnet (Bayer) dithering.
shader_type canvas_item;

uniform float levels : hint_range(2.0, 16.0) = 6.0;   // farvetrin pr. kanal
uniform float saturation : hint_range(0.0, 2.0) = 1.3; // ekstra mætning (Terraria-farver)
uniform float dither_strength : hint_range(0.0, 1.0) = 0.95;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = clamp(mix(vec3(l), c, saturation), 0.0, 1.0);
	ivec2 px = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	float b = BAYER[(px.x % 4) + (px.y % 4) * 4] / 16.0;
	c = floor(c * levels + b * dither_strength) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
