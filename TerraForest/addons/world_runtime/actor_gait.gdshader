// SPDX-License-Identifier: 0BSD
shader_type spatial;
void vertex() {
    vec3 pivot=COLOR.rgb*2.0-1.0;
    float angle=sin(INSTANCE_CUSTOM.x)*(COLOR.a-0.5)*2.0*INSTANCE_CUSTOM.y;
    float c=cos(angle),s=sin(angle);
    mat3 rotation=mat3(vec3(1,0,0),vec3(0,c,s),vec3(0,-s,c));
    VERTEX=pivot+rotation*(VERTEX-pivot);
    NORMAL=rotation*NORMAL;
}
void fragment() {
    ALBEDO=vec3(0.72,0.42,0.16);
    ROUGHNESS=0.85;
}
