shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 player_screen_uv = vec2(0.5, 0.5);
uniform float radius_px = 220.0;
uniform float feather_px = 160.0;

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 offset_px = (SCREEN_UV - player_screen_uv) * viewport_size;
	float distance_px = length(offset_px);
	float transition_start = max(radius_px - feather_px * 0.5, 0.0);
	float transition_end = radius_px + feather_px * 0.5;
	float focus = 1.0 - smoothstep(transition_start, transition_end, distance_px);

	vec3 sharp = texture(screen_texture, SCREEN_UV).rgb;
	vec2 inner = SCREEN_PIXEL_SIZE * 3.0;
	vec2 outer = SCREEN_PIXEL_SIZE * 7.0;
	vec3 blurred = sharp * 0.20;
	blurred += texture(screen_texture, SCREEN_UV + vec2(inner.x, 0.0)).rgb * 0.10;
	blurred += texture(screen_texture, SCREEN_UV - vec2(inner.x, 0.0)).rgb * 0.10;
	blurred += texture(screen_texture, SCREEN_UV + vec2(0.0, inner.y)).rgb * 0.10;
	blurred += texture(screen_texture, SCREEN_UV - vec2(0.0, inner.y)).rgb * 0.10;
	blurred += texture(screen_texture, SCREEN_UV + vec2(inner.x, inner.y)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV + vec2(inner.x, -inner.y)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV + vec2(-inner.x, inner.y)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV - inner).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV + vec2(outer.x, 0.0)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV - vec2(outer.x, 0.0)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV + vec2(0.0, outer.y)).rgb * 0.05;
	blurred += texture(screen_texture, SCREEN_UV - vec2(0.0, outer.y)).rgb * 0.05;

	COLOR = vec4(mix(blurred, sharp, focus), 1.0);
}
