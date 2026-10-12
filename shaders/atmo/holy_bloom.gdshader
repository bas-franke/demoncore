shader_type canvas_item;
// Holy chromatic bloom (AtmoScreenFX): while a boss telegraph charges, the screen around it splits
// into radial colour fringes and a golden glow blooms from its brightest parts. Reads the screen, so
// it is only drawn (rect visible) while `intensity` > 0, and only at Medium quality and up.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 center = vec2(0.5, 0.5);
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float fringe = 0.014;

void fragment() {
	vec2 d = SCREEN_UV - center;
	vec2 da = d;
	da.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(da);
	float k = clamp(intensity, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.6, dist));
	// Radial chromatic split away from the telegraph.
	vec2 off = d * fringe * k;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off).r;
	col.g = texture(screen_tex, SCREEN_UV).g;
	col.b = texture(screen_tex, SCREEN_UV - off).b;
	// Golden bloom from a blurred (mip) copy: only what is already bright glows.
	vec3 blur = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;
	float lum = dot(blur, vec3(0.299, 0.587, 0.114));
	col += tint.rgb * smoothstep(0.55, 1.2, lum) * k * 0.4;
	// A faint warm halo at the source itself.
	col += tint.rgb * k * 0.05 * (1.0 - smoothstep(0.0, 0.35, dist));
	COLOR = vec4(col, 1.0);
}
