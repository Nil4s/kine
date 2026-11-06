#pragma once
// KineTPaintNative (L53 TPAINT): texture paint with screen projection. One object = one mesh's UV layout + one RGBA8 texture.
//   setup(pos, uv, size)  3 positions and 3 uvs per triangle (fan-split faces); builds the UV coverage mask.
//   stamp(...)  a round brush in SCREEN px: each texel's surface point is projected with mvp, kept when inside the disk, front-facing and not behind
//               the depth buffer of the mesh's own front faces; texels within `pad` of an island (outside every triangle) are painted from the
//               triangle's plane continued outward (seam bleed). Each texel is written once per stamp. scripts/kmesh_tpaint.gd is the same maths.
//   begin_stroke / end_stroke / undo / redo: journal of (texel, old, new).
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cstdint>
#include <vector>

namespace godot {

class KineTPaintNative : public RefCounted {
	GDCLASS(KineTPaintNative, RefCounted)

	struct Tri {
		double p[3][3];
		double uv[3][2]; // texel units
		double inv_den = 0.0, h[3] = { 0, 0, 0 }; // 1 / uv determinant, the three heights in texels
		bool ok = false;
	};
	struct Entry {
		int32_t idx;
		uint8_t o[4], n[4];
	};
	int size = 0;
	std::vector<Tri> tris;
	std::vector<uint8_t> tex, cov, stamped, smark;
	std::vector<int32_t> touched, stouched;
	std::vector<double> depth;
	std::vector<Entry> cur;
	std::vector<std::vector<Entry>> undo_s, redo_s;
	bool in_stroke = false;

protected:
	static void _bind_methods();

public:
	static int version();
	void setup(const PackedVector3Array &p_pos, const PackedVector2Array &p_uv, int p_size);
	int stamp(const PackedFloat64Array &p_mvp, const Vector3 &p_cam, int p_w, int p_h, double p_cx, double p_cy, double p_r, const Color &p_col, double p_strength, double p_hardness, int p_pad, bool p_cull, bool p_occ);
	void begin_stroke();
	int end_stroke();
	bool undo();
	bool redo();
	PackedByteArray get_data() const;
	void set_data(const PackedByteArray &p_d);
	PackedByteArray coverage() const;
};

} // namespace godot
