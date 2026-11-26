shader_type canvas_item;
// Slight film grain: animated luminance jitter, no average brightening.
// Optional vignette (0 = off) darkens the frame edges toward the ink.

uniform float strength : hint_range(0.0, 0.3) = 0.055;
uniform float size = 640.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
        float n = hash(SCREEN_UV * vec2(size, size * 0.5625) + fract(TIME) * 97.13);
        float a = strength * abs(n - 0.5) * 2.0;
        vec3 ink = vec3(0.078, 0.071, 0.11);
        float d = distance(SCREEN_UV, vec2(0.5, 0.5));
        float v = smoothstep(0.42, 0.92, d) * vignette;
        COLOR = vec4(mix(vec3(n), ink, v), max(a, v));
}
