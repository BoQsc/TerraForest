// SPDX-License-Identifier: 0BSD
// Ordered field commands may share reconstruction, not replace one another.
// Standalone CPU correctness test; does NOT execute the Godot scheduler.
#include "../native/core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static int checks = 0, failures = 0;
static void check(bool result, const char *name) {
    ++checks; if (!result) ++failures;
    std::printf("%s %s\n", result ? "PASS" : "FAIL", name);
}
static bool request(World &world, V3 a, V3 b, float radius, bool add) {
    Bytes command, reply;
    command.u(2); command.vec(a); command.vec(b); command.f(radius);
    command.u(0); command.u(add ? 1 : 0); command.u(1);
    process_request(world, command.p, command.n, reply);
    bool valid = reply.n >= 12 && reply.p[8] == 0;
    command.release(); reply.release(); return valid;
}
static bool same_bytes(const Bytes &a, const Bytes &b) {
    return a.n == b.n && (a.n == 0 || std::memcmp(a.p,b.p,a.n) == 0);
}
static bool valid_mesh(const Mesh &mesh) {
    if (mesh.i.n % 3 != 0) return false;
    for (int i=0;i<mesh.i.n;++i) if (mesh.i[i] >= u32(mesh.v.n)) return false;
    return true;
}
static void scenario(int id, bool add, float radius, bool fitted) {
    World serial, grouped; serial.init(); grouped.init();
    serial.surface_style = grouped.surface_style = fitted ? 1 : 0;
    const float y = add ? serial.height(320,1312) + 2.f : serial.height(320,1312) - .6f;
    // Noncollinear originals, on a patch boundary. A repeated member is a no-op.
    V3 points[4] = {{318,y,1310},{320,y,1312},{322,y,1310},{322,y,1310}};
    unsigned before = 0;
    bool flags[2][4] = {};
    bool ok = true;
    for (int i=0;i<4;++i) {
        before = serial.revision;
        ok &= request(serial, points[i], points[i], radius, add);
        flags[0][i] = unsigned(serial.revision) != before;
        Mesh temporary; ok &= build_patch(serial,304,1296,32,1,temporary);
        ok &= valid_mesh(temporary); temporary.release();
    }
    for (int i=0;i<4;++i) {
        before = grouped.revision;
        ok &= request(grouped, points[i], points[i], radius, add);
        flags[1][i] = unsigned(grouped.revision) != before;
    }
    char label[180];
    std::snprintf(label,sizeof label,"case %d: all original ordered commands accepted",id); check(ok,label);
    std::snprintf(label,sizeof label,"case %d: changed/no-op membership is identical",id); check(std::memcmp(flags[0],flags[1],sizeof flags[0])==0 && !flags[0][3],label);
    Bytes a,b; serial.serialize(a); grouped.serialize(b);
    std::snprintf(label,sizeof label,"case %d: final authoritative saved field is byte-identical",id); check(same_bytes(a,b),label);
    a.release(); b.release();
    // A fresh final build of both worlds isolates final-state geometry/visibility.
    Mesh ma,mb; bool built = build_patch(serial,304,1296,32,1,ma) && build_patch(grouped,304,1296,32,1,mb);
    encode_mesh(ma,304,1296,32,1,a); encode_mesh(mb,304,1296,32,1,b);
    std::snprintf(label,sizeof label,"case %d: final geometry normals materials and light packet identical",id); check(built && valid_mesh(ma) && valid_mesh(mb) && same_bytes(a,b),label);
    a.release(); b.release(); ma.release(); mb.release(); serial.release(); grouped.release();
}
int main() {
    tr_alloc = std::malloc; tr_realloc = std::realloc; tr_free = std::free;
    scenario(1,false,1.f,false); scenario(2,true,1.f,false);
    scenario(3,false,4.f,false); scenario(4,true,4.f,false);
    scenario(5,false,1.f,true); scenario(6,true,4.f,true);
    check(!tr_oom,"no allocation failure in ordered-group tests");
    std::printf("ORDERED_GROUP_RESULT %d checks / %d failures\n",checks,failures);
    return failures ? 1 : 0;
}
