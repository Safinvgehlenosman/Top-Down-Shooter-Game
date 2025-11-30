shader_type canvas_item;

// Base colors (dark matte)
uniform vec4 body_color      = vec4(0.12, 0.14, 0.16, 1.0); // main body
uniform vec4 body_color_top  = vec4(0.18, 0.20, 0.22, 1.0); // slightly lighter top

// Border
uniform vec4 border_color    = vec4(0.30, 0.33, 0.36, 1.0); // subtle rim
uniform float border_strength = 0.8;   // 0–1 how visible the rim is

// Shape / softness
uniform float corner_radius   = 0.16;  // 0–0.5, try 0.10–0.18
uniform float edge_softness   = 0.008; // how soft the outer edge is

// Lighting
uniform float top_highlight_strength = 0.08; // brightness near top
uniform float center_darkening       = 0.05; // darken toward center a bit

// Rounded-rect signed distance in UV space [0..1]
float rounded_rect_sdf(vec2 uv, float r) {
    vec2 q = abs(uv - 0.5) - (0.5 - r);
    return length(max(q, vec2(0.0))) - r;
}

void fragment() {
    vec2 uv = UV;

    // --- shape ---
    float d = rounded_rect_sdf(uv, corner_radius);

    // soft alpha on the very outside (anti-aliased edge)
    float alpha = 1.0 - smoothstep(0.0, edge_softness, d);
    if (alpha <= 0.0) {
        discard;
    }

    // --- base vertical gradient (slight) ---
    float t = uv.y;
    vec3 base = mix(body_color_top.rgb, body_color.rgb, t);

    // --- top highlight band ---
    float top_band = 1.0 - smoothstep(0.0, 0.35, uv.y); // strongest at top
    base += vec3(top_highlight_strength) * top_band;

    // --- subtle center darkening (so edges feel lighter) ---
    float center = distance(uv, vec2(0.5));
    float center_factor = smoothstep(0.0, 0.7, center); // 0 center → 1 edges
    base -= vec3(center_darkening) * (1.0 - center_factor);

    // --- border rim (very soft, only near the edge) ---
    float border_region = smoothstep(-0.012, 0.0, d) - smoothstep(0.0, 0.012, d);
    base = mix(base, border_color.rgb, border_region * border_strength);

    COLOR = vec4(base, alpha);
}
