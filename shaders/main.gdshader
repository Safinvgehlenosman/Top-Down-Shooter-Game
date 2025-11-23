shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float noise_intensity    : hint_range(0.0, 1.0) = 0.04;
uniform float distortion         : hint_range(0.0, 0.02) = 0.005;
uniform float time_scale         : hint_range(0.0, 3.0) = 1.0;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.6;
uniform float vignette_radius   : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.2;


float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	
	
    vec2 uv = SCREEN_UV;
    float t = TIME * time_scale;

    // slight vertical wobble
	uv.y += sin(uv.y * 40.0 + t * 1.0) * distortion;


	vec4 col = texture(screen_tex, uv);


    // horizontal scanlines
    float scan = sin(uv.y * 120.0) * 0.5 + 0.5;
    col.rgb -= scanline_intensity * scan;

    // static noise
    float n = rand(vec2(uv.x * 800.0, uv.y * 600.0 + t * 10.0));
    col.rgb += (n - 0.5) * 2.0 * noise_intensity;


    COLOR = col;
}
