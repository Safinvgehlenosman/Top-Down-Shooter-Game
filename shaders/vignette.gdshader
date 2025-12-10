shader_type canvas_item;

uniform float radius : hint_range(0.0, 1.5) = 0.6;      // how far from center before darkening
uniform float softness : hint_range(0.0, 1.0) = 0.4;    // width of the fade
uniform float intensity : hint_range(0.0, 2.0) = 0.8;   // how dark the edges get
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
    // UV from 0..1 -> center at 0
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    // 0 near center, 1 at edges
    float vig = smoothstep(radius, radius + softness, dist);

    // apply intensity
    vig = clamp(vig * intensity, 0.0, 1.0);

    COLOR = vec4(color.rgb, vig * color.a);
}
