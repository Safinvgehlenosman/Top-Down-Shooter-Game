shader_type canvas_item;

uniform vec4 frost_color : source_color = vec4(0.4, 0.8, 1.0, 1.0); // Ice tint
uniform float frost_strength : hint_range(0.0, 1.0) = 0.45;        // 0.45 = subtle overlay
uniform float frost_opacity : hint_range(0.0, 1.0) = 0.2;          // Blue overlay transparency

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Keep original sprite completely intact
    vec3 original = tex.rgb;

    // Frost tint mixed into the sprite's RGB (very soft)
    vec3 tinted = mix(original, frost_color.rgb, frost_strength);

    // Add translucent frost overlay WITHOUT affecting sprite alpha
    vec3 overlay = frost_color.rgb * frost_opacity;

    COLOR = vec4(tinted + overlay, tex.a); // <-- sprite alpha unchanged!
}
