#include "kine_props_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {
struct Sup {
	float inv[9]; // row-major affine inverse basis
	float io[3]; // affine inverse origin
	float cx, cz, hx, hz;
	double y;
};

inline float dot3(const float *r, float x, float y, float z) { return r[0] * x + r[1] * y + r[2] * z; }

// Godot's Basis::invert / Transform3D::affine_inverse, same operation order, in float
void affine_inverse(const float *col, const float *o, float *inv, float *io) {
	float r[9] = { col[0], col[3], col[6], col[1], col[4], col[7], col[2], col[5], col[8] }; // rows from columns
	float c00 = r[4] * r[8] - r[5] * r[7];
	float c01 = r[5] * r[6] - r[3] * r[8];
	float c02 = r[3] * r[7] - r[4] * r[6];
	float c10 = r[2] * r[7] - r[1] * r[8];
	float c11 = r[0] * r[8] - r[2] * r[6];
	float c12 = r[1] * r[6] - r[0] * r[7];
	float c20 = r[1] * r[5] - r[2] * r[4];
	float c21 = r[2] * r[3] - r[0] * r[5];
	float c22 = r[0] * r[4] - r[1] * r[3];
	float det = r[0] * c00 + r[1] * c01 + r[2] * c02;
	float s = 1.0f / det;
	inv[0] = c00 * s; inv[1] = c10 * s; inv[2] = c20 * s;
	inv[3] = c01 * s; inv[4] = c11 * s; inv[5] = c21 * s;
	inv[6] = c02 * s; inv[7] = c12 * s; inv[8] = c22 * s;
	float nx = -o[0], ny = -o[1], nz = -o[2];
	io[0] = dot3(inv, nx, ny, nz);
	io[1] = dot3(inv + 3, nx, ny, nz);
	io[2] = dot3(inv + 6, nx, ny, nz);
}

inline int64_t key(int cx, int cz) { return ((int64_t)cx << 32) ^ (int64_t)(uint32_t)cz; }
const double CELL = 1.0;
} // namespace

int KinePropsNative::version() { return 1; }

PackedFloat64Array KinePropsNative::settle(const PackedFloat64Array &p_xf, const PackedInt32Array &p_start, const PackedFloat64Array &p_sup, const PackedByteArray &p_skip) {
	int n = (int)p_xf.size() / 12;
	PackedFloat64Array out;
	out.resize(n + 1);
	std::vector<float> oy(n);
	std::vector<int> order(n);
	for (int i = 0; i < n; i++) {
		oy[i] = (float)p_xf[12 * i + 10];
		order[i] = i;
	}
	std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return oy[a] < oy[b]; });
	std::vector<Sup> sups;
	std::vector<int> global;
	std::unordered_map<int64_t, std::vector<int>> grid;
	int moved = 0;
	for (int i : order) {
		if (i < n && i < p_skip.size() && p_skip[i]) {
			continue;
		}
		const double *x = p_xf.ptr() + 12 * i;
		float ox = (float)x[9], oz = (float)x[11];
		double y = 0.0;
		float py = oy[i];
		double lim = (double)py + 0.001;
		auto test = [&](const Sup &s) {
			if (s.y > lim || s.y <= y) return; // lower than the best so far cannot raise it
			float lx = dot3(s.inv, ox, py, oz) + s.io[0];
			float lz = dot3(s.inv + 6, ox, py, oz) + s.io[2];
			if (std::fabs((double)lx - (double)s.cx) <= (double)s.hx && std::fabs((double)lz - (double)s.cz) <= (double)s.hz) {
				y = s.y;
			}
		};
		for (int g : global) test(sups[g]);
		auto it = grid.find(key((int)std::floor(ox / CELL), (int)std::floor(oz / CELL)));
		if (it != grid.end()) {
			for (int g : it->second) test(sups[g]);
		}
		if (std::fabs(y - (double)py) > 0.0001) {
			py = (float)y;
			moved++;
		}
		out[i] = (double)py;
		// this prop now holds things up, at its settled height
		float col[9], org[3] = { ox, py, oz };
		for (int k = 0; k < 9; k++) col[k] = (float)x[k];
		float inv[9], io[3];
		affine_inverse(col, org, inv, io);
		bool upright = std::fabs(col[3]) < 1e-6f && std::fabs(col[5]) < 1e-6f && std::fabs(col[1]) < 1e-6f && std::fabs(col[7]) < 1e-6f;
		for (int si = p_start[i]; si < p_start[i + 1]; si++) {
			const double *q = p_sup.ptr() + 5 * si;
			Sup s;
			for (int k = 0; k < 9; k++) s.inv[k] = inv[k];
			for (int k = 0; k < 3; k++) s.io[k] = io[k];
			s.cx = (float)q[1]; s.cz = (float)q[2]; s.hx = (float)q[3]; s.hz = (float)q[4];
			s.y = (double)py + q[0];
			int id = (int)sups.size();
			bool placed = false;
			if (upright) {
				double x0 = 1e30, x1 = -1e30, z0 = 1e30, z1 = -1e30;
				for (int c = 0; c < 4; c++) {
					double lx = s.cx + ((c & 1) ? s.hx : -s.hx);
					double lz = s.cz + ((c & 2) ? s.hz : -s.hz);
					double wx = col[0] * lx + col[6] * lz + ox;
					double wz = col[2] * lx + col[8] * lz + oz;
					x0 = std::min(x0, wx); x1 = std::max(x1, wx);
					z0 = std::min(z0, wz); z1 = std::max(z1, wz);
				}
				x0 -= 0.02; x1 += 0.02; z0 -= 0.02; z1 += 0.02;
				int a0 = (int)std::floor(x0 / CELL), a1 = (int)std::floor(x1 / CELL);
				int b0 = (int)std::floor(z0 / CELL), b1 = (int)std::floor(z1 / CELL);
				if ((int64_t)(a1 - a0 + 1) * (b1 - b0 + 1) <= 256) {
					sups.push_back(s);
					for (int a = a0; a <= a1; a++)
						for (int b = b0; b <= b1; b++) grid[key(a, b)].push_back(id);
					placed = true;
				}
			}
			if (!placed) {
				sups.push_back(s);
				global.push_back(id);
			}
		}
	}
	for (int i = 0; i < n; i++) {
		if (i < p_skip.size() && p_skip[i]) out[i] = (double)oy[i];
	}
	out[n] = (double)moved;
	return out;
}

void KinePropsNative::_bind_methods() {
	ClassDB::bind_static_method("KinePropsNative", D_METHOD("version"), &KinePropsNative::version);
	ClassDB::bind_static_method("KinePropsNative", D_METHOD("settle", "xf", "start", "sup", "skip"), &KinePropsNative::settle);
}
