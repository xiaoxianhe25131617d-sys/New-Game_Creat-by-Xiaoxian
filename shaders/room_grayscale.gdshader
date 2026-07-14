shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec3 scene_rgb = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(scene_rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(luminance), 1.0);
}
