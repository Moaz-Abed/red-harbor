shader_type spatial;
render_mode vertex_lighting, shadows_disabled, cull_disabled;
// The PS1 plastic: every polygon snaps to the low-res grid, lighting is
// Gouraud (per-vertex), textures read point-nearest. One material for the
// whole game - tint it or give it a texture, nothing else.

uniform vec4 tint : source_color = vec4(1.0);
uniform bool textured = false;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform float glow : hint_range(0.0, 2.0) = 0.0;
uniform vec2 snap_grid = vec2(240.0, 135.0);
uniform bool affine = true;

varying vec2 v_uv;
varying float v_w;

void vertex() {
        vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
        clip.xyz /= clip.w;
        clip.xy = floor(clip.xy * snap_grid + 0.5) / snap_grid;
        clip.xyz *= clip.w;
        VERTEX = (inverse(MODELVIEW_MATRIX) * (inverse(PROJECTION_MATRIX) * clip)).xyz;
        v_w = clip.w;
        v_uv = UV * uv_scale;
        if (affine) {
                // carry uv * w so the hardware lerp cancels back to screen-linear:
                // the PS1 texture swim, no perspective correction anywhere
                v_uv *= clip.w;
        }
}

void fragment() {
        vec3 base = tint.rgb;
        if (textured) {
                vec2 uv = affine ? (v_uv / v_w) : v_uv;
                base *= texture(tex, uv).rgb;
        }
        ALBEDO = base;
        EMISSION = base * glow;
        SPECULAR = 0.0;
}
