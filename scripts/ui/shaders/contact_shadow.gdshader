// Soft dark ellipse under the puzzle, lying on the cubing mat (V.3).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

uniform float strength = 0.85;

void fragment() {
	float d = clamp(length(UV - 0.5) * 2.0, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * pow(1.0 - d, 1.8);
}
