// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
uniform vec4 tint:source_color=vec4(.51,.85,.73,1.0);
void fragment(){
    // Barycentric edges: straight lines with a light face tint.
    // Depth testing keeps buried/occluded geometry out of view.
    vec3 barycentric=vec3(UV,1.0-UV.x-UV.y);
    vec3 width=max(fwidth(barycentric),vec3(.0001));
    vec3 inside=smoothstep(vec3(0.0),width*1.25,barycentric);
    float edge=1.0-min(inside.x,min(inside.y,inside.z));
    ALBEDO=tint.rgb;
    ALPHA=.025+edge*.70;
}
