shader_type spatial;
// Opt-in silhouette outline (inverted hull, constant width in screen pixels). NOT a general ink
// line: SINBOUND has no outlines on ordinary content (see docs/team/art-style.md). Use it only to
// flag gameplay emphasis: elites (holy gold), interactables / shopkeepers (ember), the selected
// target. Put it on GeometryInstance3D.material_overlay (ArtStyle.outline() does that for a whole
// model), so it works on skinned GLB characters and never touches shared materials.
// Hard-edged meshes (split normals) would show gaps at their corners, so the extrusion direction
// comes from `outline_mode` (instance uniform, set per mesh by ArtStyle.outline()):
//   0 = NORMAL (smooth meshes, skinned meshes)
//   1 = radial in screen space from the projected origin (Art primitives: box / prism / cylinder)
//   2 = CUSTOM0.xyz, smoothed normals baked by ArtStyle (merged / imported rigid ArrayMeshes)
// Interior lines: ArtStyle chains this after outline_mask.gdshader, which stamps the body into the
// stencil (ref 64); this pass only draws where the stencil is NOT 64, i.e. outside the silhouette.
// Both run in the transparent pass (after all opaque), ordered by render_priority (mask first).
// Used alone (no mask) it still works, with the interior lines.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 64;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.38, 1.0);
// HDR multiplier: > 1 blooms.
uniform float energy = 1.6;
// Width in pixels at 1080p (scaled with the viewport height).
uniform float width = 2.5;
// 0 = steady, 1 = slow strong breathing (interactables).
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_rate = 2.4;
// Explicit slot: instance uniforms are packed per GeometryInstance BY INDEX, shared by all of its
// materials. Without the hint this would take slot 0 = lit_common's `flash`, so setting
// outline_mode painted the whole body with the white hit flash (round-4 bug). lit_common uses
// slots 0..3 (flash, dissolve, dissolve_color, rim_color).
instance uniform float outline_mode : instance_index(8) = 0.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Pixels -> NDC: 2 / viewport size; NDC -> clip: * w.
	vec2 px = vec2(width * VIEWPORT_SIZE.y / 1080.0) * 2.0 / VIEWPORT_SIZE * clip.w;
	if (outline_mode > 0.5 && outline_mode < 1.5) {
		// Radial (convex primitives): push each projected vertex away from the projected centre by
		// `width` on BOTH screen axes. Corners shared by several faces get the same offset (no gaps)
		// and a convex outline grows by at least `width` everywhere.
		vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
		vec2 d = clip.xy / clip.w - c0.xy / c0.w;
		clip.xy += sign(d) * px;
	} else {
		vec3 n = outline_mode > 1.5 ? CUSTOM0.xyz : NORMAL;
		vec2 dir = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * n, 0.0)).xy;
		float dl = length(dir);
		if (dl > 1e-5) {
			clip.xy += dir / dl * px;
		}
	}
	POSITION = clip;
}

void fragment() {
	float b = 1.0 - pulse * (0.5 - 0.5 * sin(TIME * pulse_rate));
	ALBEDO = color.rgb * energy * b;
	// Transparent pass (after every opaque body has been drawn and masked); fully opaque look.
	ALPHA = 1.0;
}
