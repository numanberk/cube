// The main screen's background (task V.3, D15 "lo-fi cubing desk"): a dark gradient with a warm desk-lamp glow
// behind the stage, a few out-of-focus bokeh lights drifting very slowly, a vignette and a faint grain.
// One full-screen pass with no textures. Graphics Low doesn't use it (main.gd removes the material, leaving the
// ColorRect's flat `bg` colour). `drift` = 0 stops the bokeh (Reduce motion). main.gd sets base_top/base_bottom from
// the palette's `bg` and lamp_center from the puzzle's place.
// TIME wraps every hour (Godot's default rollover): the drift moves exactly 2 × BOKEH_PERIOD cells an hour and the
// bokeh pattern repeats every BOKEH_PERIOD cells, so the wrap is invisible. Hash inputs stay small (old GPUs' sin()).
shader_type canvas_item;

uniform vec4 base_top : source_color = vec4(0.082, 0.086, 0.106, 1.0);
uniform vec4 base_bottom : source_color = vec4(0.055, 0.059, 0.075, 1.0);
uniform vec4 lamp_color : source_color = vec4(0.40, 0.31, 0.21, 1.0);
uniform vec2 lamp_center = vec2(0.28, 0.42);   // in screen UV; main.gd puts it behind the puzzle
uniform float lamp_strength = 0.2;
uniform float bokeh_strength = 0.05;
uniform float vignette = 0.55;
uniform float grain = 0.012;
uniform float drift = 1.0;

const float BOKEH_RATE = 0.01;    // screen heights a second; × 3600 s × 5.5 cells = 198 cells an hour
const float BOKEH_PERIOD = 99.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // width / height
	vec3 colour = mix(base_top.rgb, base_bottom.rgb, uv.y);

	// The lamp: a wide warm pool, stretched sideways like light falling on a desk.
	vec2 to_lamp = (uv - lamp_center) * vec2(aspect * 0.75, 1.0);
	colour += lamp_color.rgb * lamp_strength * exp(-dot(to_lamp, to_lamp) * 6.0);

	// Bokeh: soft discs on a coarse grid, each cell one light (or none), drifting up very slowly.
	float t = TIME * BOKEH_RATE * drift;
	vec2 grid_uv = vec2(uv.x * aspect, uv.y + t) * 5.5;
	vec2 cell = floor(grid_uv);
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 here = cell + vec2(float(dx), float(dy));
			vec2 c = mod(here, vec2(BOKEH_PERIOD));  // the light's identity: repeats every BOKEH_PERIOD cells
			float h = hash(c);
			if (h > 0.62) {
				vec2 centre = here + vec2(hash(c + 7.1), hash(c + 3.7));
				float radius = 0.14 + 0.2 * hash(c + 1.3);
				float d = length(grid_uv - centre) / radius;
				float disc = smoothstep(1.0, 0.82, d) * (0.55 + 0.45 * smoothstep(0.6, 1.0, d));  // brighter rim
				vec3 tint = mix(vec3(1.0, 0.72, 0.42), vec3(0.55, 0.7, 1.0), step(0.85, h));     // mostly warm
				colour += tint * disc * bokeh_strength * (0.5 + 0.5 * hash(c + 9.9));
			}
		}
	}

	// Vignette and grain.
	vec2 centred = (uv - 0.5) * vec2(aspect, 1.0) / aspect;
	colour *= 1.0 - vignette * smoothstep(0.25, 0.85, length(centred) * 1.25);
	colour += (hash(mod(FRAGCOORD.xy, 251.0)) - 0.5) * grain;
	COLOR = vec4(colour, 1.0);
}
