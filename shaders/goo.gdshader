shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Turns the low-resolution goo field into smooth glossy jelly.
//
// The field texture holds one soft blob per gob, added together, with one
// color channel per flavor riding the belt (three per tile, tiles side by
// side). Where a flavor's channel is above the threshold there is jelly of
// that flavor; overlapping gobs saturate, so a heap is one even surface. The
// rim shade and the highlight come from comparing the field with itself a few
// pixels toward and away from the light, which costs two extra samples and
// needs no normals.

uniform sampler2D field : filter_linear, repeat_disable;
uniform int tiles = 1;
uniform vec3 colors[6];
// One board pixel, in this rect's UV units.
uniform vec2 px = vec2(0.001);
uniform float threshold = 0.5;
uniform float light_reach = 9.0;
uniform float gloss = 0.85;
uniform vec2 shadow_offset = vec2(5.0, 12.0);
uniform float shadow_strength = 0.3;

vec3 tile_at(vec2 uv, int tile) {
	return texture(field, vec2((clamp(uv.x, 0.0, 1.0) + float(tile)) / float(tiles), uv.y)).rgb;
}

float channel(vec2 uv, int ch) {
	vec3 v = tile_at(uv, ch / 3);
	int k = ch - (ch / 3) * 3;
	return k == 0 ? v.r : (k == 1 ? v.g : v.b);
}

// The strongest flavor at uv: its field value in x, its channel in y.
vec2 strongest(vec2 uv) {
	vec3 a = tile_at(uv, 0);
	vec2 best = vec2(a.r, 0.0);
	if (a.g > best.x) best = vec2(a.g, 1.0);
	if (a.b > best.x) best = vec2(a.b, 2.0);
	if (tiles > 1) {
		vec3 b = tile_at(uv, 1);
		if (b.r > best.x) best = vec2(b.r, 3.0);
		if (b.g > best.x) best = vec2(b.g, 4.0);
		if (b.b > best.x) best = vec2(b.b, 5.0);
	}
	return best;
}

void fragment() {
	vec2 top = strongest(UV);
	float f = top.x;
	int ch = int(top.y + 0.5);
	float soft = clamp(fwidth(f), 0.004, 0.2);
	float mask = smoothstep(threshold - soft, threshold + soft, f);

	vec2 to_light = normalize(vec2(-0.55, -0.83)) * px * light_reach;
	float lit = f - channel(UV + to_light, ch);
	float shaded = f - channel(UV - to_light, ch);
	vec3 c = colors[ch];
	c *= mix(0.84, 1.0, smoothstep(threshold, 0.96, f));
	c *= 1.0 - 0.2 * smoothstep(0.12, 0.6, shaded);
	c = mix(c, vec3(1.0), 0.14 * smoothstep(0.08, 0.5, lit));
	float shine = smoothstep(0.2, 0.3, lit) * smoothstep(threshold + 0.2, threshold + 0.32, f);
	c = mix(c, vec3(1.0), shine * gloss);

	float under = strongest(UV - shadow_offset * px).x;
	float shadow = smoothstep(threshold - 0.22, threshold + 0.1, under) * shadow_strength;
	float alpha = mask + shadow * (1.0 - mask);
	vec3 rgb = mix(vec3(0.24, 0.12, 0.04), c, alpha > 0.0 ? mask / alpha : 1.0);
	COLOR = vec4(rgb, alpha);
}
