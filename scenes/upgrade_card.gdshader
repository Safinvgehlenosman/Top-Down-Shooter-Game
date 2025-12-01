shader_type canvas_item;

uniform float pulse_strength : hint_range(0.0, 1.0) = 0.35;
uniform float pulse_speed    : hint_range(0.0, 20.0) = 6.0;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float glow_softness  : hint_range(0.0, 0.5) = 0.15;
uniform vec4 glow_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // How bright the pixel is
    float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

    // 0 on dark card body, 1 on bright border
    float edge_mask = smoothstep(glow_threshold,
                                 glow_threshold + glow_softness,
                                 lum);

    // Breathing pulse over time
    float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;

    vec3 base_rgb = tex.rgb;
    vec3 glow_rgb = base_rgb * pulse * glow_tint.rgb;

    // Only apply glow on bright pixels (the outline)
    vec3 final_rgb = mix(base_rgb, glow_rgb, edge_mask * glow_tint.a);

    COLOR = vec4(final_rgb, tex.a);
}
