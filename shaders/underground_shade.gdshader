shader_type canvas_item;
render_mode unshaded;

uniform vec4 fog_color : source_color = vec4(0.025, 0.022, 0.03, 1.0);
uniform float top_alpha : hint_range(0.0, 1.0) = 0.05;
uniform float bottom_alpha : hint_range(0.0, 1.0) = 0.88;
uniform float mist_strength : hint_range(0.0, 0.2) = 0.055;

float fog_noise(vec2 uv) {
	float broad_mist = sin(uv.x * 41.0 + sin(uv.y * 13.0) * 2.4);
	float fine_mist = sin(uv.x * 113.0 - uv.y * 29.0);
	return broad_mist * 0.65 + fine_mist * 0.35;
}

void fragment() {
	float depth = smoothstep(0.0, 1.0, UV.y);
	float mist = fog_noise(UV) * mist_strength * smoothstep(0.05, 0.65, depth);
	float alpha = clamp(mix(top_alpha, bottom_alpha, pow(depth, 0.72)) + mist, 0.0, 1.0);
	COLOR = vec4(fog_color.rgb, alpha);
}
