shader_type canvas_item;
// The tube finish over the upscaled frame: 5-bit color with an ordered
// Bayer dither, faint scanlines and a dark vignette. Runs above everything.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float scan : hint_range(0.0, 1.0) = 0.12;
uniform float vignette : hint_range(0.0, 1.0) = 0.30;

float bayer(vec2 px) {
        int x = int(mod(px.x, 4.0));
        int y = int(mod(px.y, 4.0));
        int i = y * 4 + x;
        int t = 0;
        if (i == 0) { t = 0; } else if (i == 1) { t = 8; } else if (i == 2) { t = 2; } else if (i == 3) { t = 10; }
        else if (i == 4) { t = 12; } else if (i == 5) { t = 4; } else if (i == 6) { t = 14; } else if (i == 7) { t = 6; }
        else if (i == 8) { t = 3; } else if (i == 9) { t = 11; } else if (i == 10) { t = 1; } else if (i == 11) { t = 9; }
        else if (i == 12) { t = 15; } else if (i == 13) { t = 7; } else if (i == 14) { t = 13; } else { t = 5; }
        return float(t) / 16.0;
}

void fragment() {
        vec3 c = texture(screen_tex, SCREEN_UV).rgb;
        float d = bayer(FRAGCOORD.xy) - 0.5;
        c = floor(c * 31.0 + d * 1.5) / 31.0;
        float line = 1.0 - scan * step(0.5, fract(FRAGCOORD.y * 0.5));
        c *= line;
        float v = smoothstep(0.55, 1.0, distance(SCREEN_UV, vec2(0.5, 0.5)));
        c *= 1.0 - vignette * v;
        COLOR = vec4(c, 1.0);
}
