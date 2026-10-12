// Shared physically based light() for lit / lit_static / toon / ground shaders.
// Lambert diffuse + GGX specular (Smith-correlated visibility, Schlick fresnel), with the drifting
// cloud shadows (cloud.gdshaderinc) applied to the directional sun only.
// The including shader must declare `varying float cloud;` and write it in fragment().
// Define LIT_SHEEN (and declare `uniform float sheen`) for wrapped diffuse + soft rim (cloth, skin).

void light() {
	float ndl_raw = dot(NORMAL, LIGHT);
	float ndl = clamp(ndl_raw, 0.0, 1.0);
	float att = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		att *= cloud;
	}
	vec3 lc = LIGHT_COLOR / PI;
	float diff = ndl;
#ifdef LIT_SHEEN
	float w = sheen * 0.45;
	diff = clamp((ndl_raw + w) / (1.0 + w), 0.0, 1.0);
#endif
	DIFFUSE_LIGHT += diff * att * lc;
	if (ndl > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
		float ndv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
		float ldh = clamp(dot(LIGHT, h), 0.0, 1.0);
		float a = max(ROUGHNESS * ROUGHNESS, 0.002);
		float a2 = a * a;
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float D = a2 / (PI * dd * dd);
		float V = 0.5 / max(ndl * (ndv * (1.0 - a) + a) + ndv * (ndl * (1.0 - a) + a), 1e-4);
		vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
		vec3 F = f0 + (1.0 - f0) * pow(1.0 - ldh, 5.0);
		SPECULAR_LIGHT += D * V * F * ndl * att * lc * SPECULAR_AMOUNT * 2.0;
	}
#ifdef LIT_SHEEN
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += fres * sheen * smoothstep(-0.35, 0.6, ndl_raw) * att * lc * 0.9;
#endif
}
