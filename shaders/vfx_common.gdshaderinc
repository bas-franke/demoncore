// Shared helpers for the combat VFX shaders (res://shaders/vfx_*.gdshader, res://scenes/vfx/).
// Billboard / velocity-streak model-view matrices for particle quads, soft-particle depth fade
// and cheap 2D value noise.

float vfx_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vfx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(vfx_hash(i), vfx_hash(i + vec2(1.0, 0.0)), f.x),
		mix(vfx_hash(i + vec2(0.0, 1.0)), vfx_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float vfx_fbm(vec2 p) {
	return vfx_noise(p) * 0.6 + vfx_noise(p * 2.3 + 7.1) * 0.3 + vfx_noise(p * 5.1 + 3.7) * 0.1;
}

// Camera-facing quad that keeps the model's scale (uniform particle scale).
mat4 vfx_billboard(mat4 model, mat4 view, mat4 inv_view, float roll) {
	float s = length(model[0].xyz);
	vec3 r = inv_view[0].xyz;
	vec3 u = inv_view[1].xyz;
	float c = cos(roll);
	float sn = sin(roll);
	vec3 rr = r * c + u * sn;
	vec3 uu = -r * sn + u * c;
	return view * mat4(vec4(rr * s, 0.0), vec4(uu * s, 0.0), vec4(inv_view[2].xyz * s, 0.0), model[3]);
}

// Quad stretched along the model's Y axis (particle_flag_align_y = velocity direction), turned
// around that axis to face the camera. `width` / `stretch` scale the quad's X / Y.
mat4 vfx_streak(mat4 model, mat4 view, mat4 inv_view, float width, float stretch) {
	vec3 o = model[3].xyz;
	vec3 d = model[1].xyz;
	float len = length(d);
	d /= max(len, 1e-5);
	vec3 to_cam = normalize(inv_view[3].xyz - o);
	vec3 side = cross(d, to_cam);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : inv_view[0].xyz;
	vec3 nrm = cross(side, d);
	return view * mat4(vec4(side * len * width, 0.0), vec4(d * len * stretch, 0.0), vec4(nrm, 0.0), vec4(o, 1.0));
}

// 0..1 fade where the quad meets opaque geometry (soft particles). `vtx` = fragment VERTEX.
float vfx_soft(sampler2D depth_tex, vec2 suv, mat4 inv_proj, vec3 vtx, float dist) {
	float d = texture(depth_tex, suv).r;
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, d, 1.0);
	float scene_z = v.z / v.w;
	return clamp((vtx.z - scene_z) / dist, 0.0, 1.0);
}
