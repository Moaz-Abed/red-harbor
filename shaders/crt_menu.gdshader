shader_type canvas_item;
// Retro CRT post-process: chromatic split, scanlines, rolling band, glitch
// tears, vignette. Drive `aberration`/`glitch`/`flash` from GDScript for punch.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float aberration : hint_range(0.0, 8.0) = 1.2;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float barrel : hint_range(0.0, 0.12) = 0.045;
uniform float dim : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
        vec2 uv = SCREEN_UV;
        vec2 cc = uv - 0.5;
        // tube curvature
        uv += cc * dot(cc, cc) * barrel * 2.0;
        // glitch: displaced horizontal bands
        if (glitch > 0.01) {
                float band = floor(uv.y * 40.0);
                float seed = hash(vec2(band, floor(TIME * 13.0)));
                if (seed > 1.0 - glitch * 0.4) {
                        uv.x += (hash(vec2(band, TIME)) - 0.5) * glitch * 0.12;
                }
        }
        // chromatic aberration, stronger at the edges
        vec2 px = aberration * SCREEN_PIXEL_SIZE * (0.5 + dot(cc, cc) * 3.0);
        vec3 col;
        col.r = texture(screen_tex, uv + px).r;
        col.g = texture(screen_tex, uv).g;
        col.b = texture(screen_tex, uv - px).b;
        // scanlines
        col *= 0.82 + 0.18 * sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159);
        // slow rolling bright band
        col *= 1.0 + 0.05 * smoothstep(0.92, 1.0, fract(uv.y * 0.7 - TIME * 0.06));
        // static
        col += (hash(uv * vec2(640.0, 360.0) + fract(TIME) * 61.7) - 0.5) * 0.045;
        // vignette + out-of-tube black
        float vig = 1.0 - dot(cc, cc) * 1.1;
        col *= clamp(vig, 0.0, 1.0);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
                col = vec3(0.0);
        }
        col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0));
        col *= (1.0 - dim);
        COLOR = vec4(col, 1.0);
}
