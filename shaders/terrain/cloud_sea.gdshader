shader_type spatial;
// Endless sea of sunlit clouds far below the floating islands of the heavens (a big plane under a
// TerrainPatch with Edge.DROP_DOWN). World-space billows drift slowly; bright tops, lavender-grey
// shadowed hollows, golden sheen where the sun grazes; fades into haze with distance to the camera.
// Unshaded (self-lit) so it reads as luminous depth, not as a floor.
render_mode unshaded, cull_back, fog_disabled;

uniform vec3 top_color : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 low_color : source_color = vec3(0.55, 0.52, 0.66);
uniform vec3 sun_color : source_color = vec3(1.0, 0.82, 0.5);
uniform vec3 haze_color : source_color = vec3(0.86, 0.82, 0.86);
uniform vec2 drift = vec2(0.6, 0.25);
uniform float scale = 0.045;
uniform float energy = 1.0;
// Seamless fbm texture (res://assets/textures/ground_noise.png, RGBA = 4 fields); TerrainPatch
// assigns it. Texture noise avoids the lattice streaks hash noise shows at this huge scale.
uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (world_pos.xz - drift * TIME) * scale;
	vec4 n1 = texture(noise_tex, p * 0.35);
	vec4 n2 = texture(noise_tex, p * 0.9 + vec2(0.37, 0.71) + TIME * 0.002);
	float b = n1.r * 0.65 + n2.g * 0.35;
	float billow = smoothstep(0.35, 0.7, b);
	// cauliflower billows: bright domes, warm sun-kissed crowns, lavender hollows between them
	float dome = smoothstep(0.5, 0.8, n2.b) * billow;
	vec3 col = mix(low_color, top_color, billow);
	col = mix(col, top_color * 1.05 + sun_color * 0.12, dome);
	float dist = length(world_pos - INV_VIEW_MATRIX[3].xyz);
	col = mix(col, haze_color, smoothstep(30.0, 90.0, dist) * 0.7);
	ALBEDO = col * energy;
}
