shader_type canvas_item;

// Alpha slime visual effect - purple tint with pulsating glow
uniform vec4 alpha_tint_color : source_color = vec4(0.8, 0.4, 1.0, 1.0); // Purple/magenta tint
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.3;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	// Sample the base texture
	vec4 base_color = texture(TEXTURE, UV);
	
	// Apply alpha tint while preserving alpha channel
	vec3 tinted = mix(base_color.rgb, alpha_tint_color.rgb, 0.5);
	
	// Create pulsating effect using sine wave
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5; // Oscillates 0.0 to 1.0
	float brightness_boost = 1.0 + (pulse * pulse_strength);
	
	// Apply pulse and tint
	COLOR.rgb = tinted * brightness_boost;
	COLOR.a = base_color.a; // Preserve original transparency
}
