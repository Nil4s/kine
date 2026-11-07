#include "kine_dock_native.h"

using namespace godot;

void KineDockNative::_bind_methods() {
	ClassDB::bind_static_method("KineDockNative", D_METHOD("version"), &KineDockNative::version);
	ClassDB::bind_static_method("KineDockNative", D_METHOD("push", "vs", "dv", "ai", "amp"), &KineDockNative::push);
	ClassDB::bind_static_method("KineDockNative", D_METHOD("first_free", "spots", "w", "h", "body", "avoid", "pts", "pad"), &KineDockNative::first_free);
}

int KineDockNative::version() {
	return 1;
}

int KineDockNative::first_free(const PackedFloat64Array &p_spots, double p_w, double p_h, const Rect2 &p_body, bool p_avoid, const PackedVector2Array &p_pts, double p_pad) {
	const float w = (float)p_w;
	const float h = (float)p_h;
	const float pad = (float)p_pad;
	const float bx = p_body.position.x, by = p_body.position.y;
	const float bex = p_body.size.x, bey = p_body.size.y; // sizes; the ends are summed per test, as Rect2::intersects does
	const int64_t n = p_spots.size() / 2;
	const double *sp = p_spots.ptr();
	const Vector2 *pp = p_pts.ptr();
	const int64_t np = p_pts.size();
	for (int64_t i = 0; i < n; i++) {
		const float x = (float)sp[2 * i];
		const float y = (float)sp[2 * i + 1];
		if (p_avoid) {
			// Rect2(x, y, w, h).intersects(body): the body's end is body.position + body.size
			bool hit = true;
			if (x >= (bx + bex)) {
				hit = false;
			} else if ((x + w) <= bx) {
				hit = false;
			} else if (y >= (by + bey)) {
				hit = false;
			} else if ((y + h) <= by) {
				hit = false;
			}
			if (hit) {
				continue;
			}
		}
		// Rect2.grow(pad): position - pad, size + pad * 2; then has_point
		const float gx = x - pad;
		const float gy = y - pad;
		const float gw = w + pad * 2.0f;
		const float gh = h + pad * 2.0f;
		bool covered = false;
		for (int64_t k = 0; k < np; k++) {
			const float px = pp[k].x;
			const float py = pp[k].y;
			if (px < gx || py < gy) {
				continue;
			}
			if (px >= (gx + gw) || py >= (gy + gh)) {
				continue;
			}
			covered = true;
			break;
		}
		if (!covered) {
			return (int)i;
		}
	}
	return -1;
}

PackedVector3Array KineDockNative::push(const PackedVector3Array &p_vs, const PackedVector3Array &p_dv, const PackedInt32Array &p_ai, double p_amp) {
	PackedVector3Array out = p_vs;
	const float amp = (float)p_amp;
	const int64_t n = out.size();
	const int64_t nd = p_dv.size();
	Vector3 *o = out.ptrw();
	const Vector3 *d = p_dv.ptr();
	const int32_t *a = p_ai.ptr();
	for (int64_t k = 0; k < p_ai.size(); k++) {
		const int32_t i = a[k];
		if (i < 0 || i >= n || i >= nd) {
			continue;
		}
		const float mx = d[i].x * amp;
		const float my = d[i].y * amp;
		const float mz = d[i].z * amp;
		o[i].x = o[i].x + mx;
		o[i].y = o[i].y + my;
		o[i].z = o[i].z + mz;
	}
	return out;
}
