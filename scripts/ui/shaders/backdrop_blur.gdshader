shader_type canvas_item;
// Behind an open panel (V.6, Graphics High): the screen, softly blurred and darkened. Cheap: 13 taps.
// `dim` darkens like the plain Low-quality dim; COLOR.a (the node's fade) fades the whole effect in and out.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float radius = 3.0;   // blur radius in screen pixels
uniform float dim = 0.55;     // how dark, like the Low dim's alpha
uniform float base_alpha = 0.55;  // the ColorRect's own alpha (its Low-quality dim): divided out, so the blur is opaque

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 sum = texture(screen_texture, SCREEN_UV).rgb * 0.2;
	sum += texture(screen_texture, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.1;
	sum += texture(screen_texture, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.1;
	sum += texture(screen_texture, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.1;
	sum += texture(screen_texture, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.1;
	sum += texture(screen_texture, SCREEN_UV + px).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV - px).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV + vec2(px.x, -px.y)).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV + vec2(-px.x, px.y)).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV + vec2(2.0 * px.x, 0.0)).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV - vec2(2.0 * px.x, 0.0)).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV + vec2(0.0, 2.0 * px.y)).rgb * 0.05;
	sum += texture(screen_texture, SCREEN_UV - vec2(0.0, 2.0 * px.y)).rgb * 0.05;
	COLOR = vec4(sum * (1.0 - dim), clamp(COLOR.a / base_alpha, 0.0, 1.0));
}
