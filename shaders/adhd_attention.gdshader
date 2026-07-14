shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 player_screen_uv = vec2(0.5, 0.5);
uniform float radius_px = 220.0;
uniform float feather_px = 160.0;
uniform float outer_saturation = 0.52;
uniform float outer_brightness = 0.84;
uniform float time_sec = 0.0;

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 offset_px = (SCREEN_UV - player_screen_uv) * viewport_size;
	float distance_px = length(offset_px);
	float transition_start = max(radius_px - feather_px * 0.5, 0.0);
	float transition_end = radius_px + feather_px * 0.5;
	float focus = 1.0 - smoothstep(transition_start, transition_end, distance_px);

	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, 1.25).rgb;
	float luminance = dot(blurred, vec3(0.299, 0.587, 0.114));
	vec3 muted = mix(vec3(luminance), blurred, outer_saturation);
	float pulse = 1.0 + 0.012 * sin(time_sec * 3.2);
	vec3 peripheral = muted * outer_brightness * pulse;

	COLOR = vec4(mix(peripheral, sharp, focus), 1.0);
}
