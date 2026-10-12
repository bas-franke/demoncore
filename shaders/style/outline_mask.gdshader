shader_type spatial;
// First pass of the silhouette outline (ArtStyle.outline()): draws the model's own body into the
// stencil buffer (ref 64) without changing the color, so the hull pass (outline.gdshader, its
// next_pass, rendered later via render_priority) only lands OUTSIDE the silhouette. That removes
// the interior lines an inverted hull draws where one body part overlaps another.
// Additive black = no visible color; transparent pass so it runs after all opaque geometry.
// No depth test: occluded body parts still mask (the hull itself is depth-tested).
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_back, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 64;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
