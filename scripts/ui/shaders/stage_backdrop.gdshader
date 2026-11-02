// Stage behind the puzzle: a soft radial glow. It fades to fully transparent at the edges, so the real UI
// background shows through there (the SubViewport is transparent) and the view has no visible border.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(0.24, 0.26, 0.32, 1.0);
uniform float strength = 0.9;
uniform float falloff = 1.4;

void fragment() {
	float d = clamp(length(UV - 0.5) * 2.0, 0.0, 1.0);
	ALBEDO = glow_color.rgb;
	ALPHA = strength * pow(1.0 - d, falloff);
}
