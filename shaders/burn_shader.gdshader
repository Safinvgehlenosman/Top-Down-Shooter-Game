shader_type canvas_item;

uniform vec4 burn_color : source_color = vec4(1.0, 0.5, 0.1, 1.0); // orange fire tint
uniform float flash_strength : hint_range(0.0, 1.0) = 0.6;         // how strong the flash is
uniform float flash_speed : hint_range(0.1, 10.0) = 4.0;           // speed of flashing

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    vec3 original = tex.rgb;

    // Flash factor oscillates between 0 → 1 → 0
    float flash = (sin(TIME * flash_speed) * 0.5) + 0.5;

    // Mix original sprite with burn flash color
    vec3 tinted = mix(original, burn_color.rgb, flash * flash_strength);

    COLOR = vec4(tinted, tex.a);
}
