shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 player_screen_uv = vec2(0.5, 0.5);
uniform float radius_px = 80.0;
uniform float feather_px = 16.0;

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 screen_position_px = SCREEN_UV * viewport_size;
	vec2 player_position_px = player_screen_uv * viewport_size;
	float distance_px = distance(screen_position_px, player_position_px);
	float visible_amount = 1.0 - smoothstep(radius_px - feather_px, radius_px, distance_px);

	vec3 scene_rgb = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(scene_rgb, vec3(0.299, 0.587, 0.114));
	vec3 grayscale_color = vec3(luminance);
	COLOR = vec4(mix(vec3(0.0), grayscale_color, visible_amount), 1.0);
}
