#include "kine_render_native.h"

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <thread>
#include <vector>

using namespace godot;

int KineRenderNative::version() { return 2; }

PackedFloat32Array KineRenderNative::accumulate_var(const Array &p_imgs) {
	PackedFloat32Array out;
	const int n = p_imgs.size();
	if (n == 0) {
		return out;
	}
	std::vector<PackedByteArray> keep;
	std::vector<const uint8_t *> ptr;
	int64_t len = -1;
	for (int i = 0; i < n; i++) {
		PackedByteArray b = p_imgs[i];
		if (len < 0) {
			len = b.size();
		}
		if (b.size() != len || len % 3 != 0) {
			return out;
		}
		keep.push_back(b);
	}
	for (auto &b : keep) {
		ptr.push_back(b.ptr());
	}
	const int64_t np = len / 3;
	out.resize(len + np);
	float *o = out.ptrw();
	const float k = 1.0f / (255.0f * (float)n);
	auto work = [&](int64_t a, int64_t b) {
		for (int64_t px = a; px < b; px++) {
			uint32_t sr = 0, sg = 0, sb = 0;
			float sl = 0, sl2 = 0;
			for (int i = 0; i < n; i++) {
				const uint8_t *p = ptr[i] + px * 3;
				sr += p[0];
				sg += p[1];
				sb += p[2];
				const float l = (0.2126f * p[0] + 0.7152f * p[1] + 0.0722f * p[2]) * (1.0f / 255.0f);
				sl += l;
				sl2 += l * l;
			}
			o[px * 3] = (float)sr * k;
			o[px * 3 + 1] = (float)sg * k;
			o[px * 3 + 2] = (float)sb * k;
			float v = 0;
			if (n > 1) {
				const float m = sl / (float)n;
				v = std::max(0.0f, sl2 / (float)n - m * m) / (float)(n - 1);
			}
			o[len + px] = v;
		}
	};
	unsigned hw = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
	if (np < 20000) {
		hw = 1;
	}
	std::vector<std::thread> th;
	const int64_t per = (np + hw - 1) / hw;
	for (unsigned t = 0; t < hw; t++) {
		const int64_t a = (int64_t)t * per, b = std::min(np, a + per);
		if (a >= b) {
			break;
		}
		if (hw == 1) {
			work(a, b);
		} else {
			th.emplace_back(work, a, b);
		}
	}
	for (auto &t : th) {
		t.join();
	}
	return out;
}

PackedFloat32Array KineRenderNative::accumulate(const Array &p_imgs) {
	PackedFloat32Array out;
	const int n = p_imgs.size();
	if (n == 0) {
		return out;
	}
	std::vector<PackedByteArray> keep;
	std::vector<const uint8_t *> ptr;
	int64_t len = -1;
	for (int i = 0; i < n; i++) {
		PackedByteArray b = p_imgs[i];
		if (len < 0) {
			len = b.size();
		}
		if (b.size() != len) {
			return out;
		}
		keep.push_back(b);
	}
	for (auto &b : keep) {
		ptr.push_back(b.ptr());
	}
	out.resize(len);
	float *o = out.ptrw();
	const float k = 1.0f / (255.0f * (float)n);
	auto work = [&](int64_t a, int64_t b) {
		const int64_t CH = 4096;
		std::vector<uint32_t> acc(CH);
		for (int64_t s = a; s < b; s += CH) {
			const int64_t m = std::min(CH, b - s);
			std::fill(acc.begin(), acc.begin() + m, 0u);
			for (int i = 0; i < n; i++) {
				const uint8_t *p = ptr[i] + s;
				for (int64_t j = 0; j < m; j++) {
					acc[j] += p[j];
				}
			}
			for (int64_t j = 0; j < m; j++) {
				o[s + j] = (float)acc[j] * k;
			}
		}
	};
	unsigned hw = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
	if (len < (1 << 16)) {
		hw = 1;
	}
	std::vector<std::thread> th;
	const int64_t per = (len + hw - 1) / hw;
	for (unsigned t = 0; t < hw; t++) {
		const int64_t a = (int64_t)t * per, b = std::min(len, a + per);
		if (a >= b) {
			break;
		}
		if (hw == 1) {
			work(a, b);
		} else {
			th.emplace_back(work, a, b);
		}
	}
	for (auto &t : th) {
		t.join();
	}
	return out;
}

PackedFloat32Array KineRenderNative::denoise(const PackedFloat32Array &p_rgb, const PackedFloat32Array &p_guide, int p_w, int p_h, int p_iters, double p_sigma_c, double p_sigma_g, const PackedFloat32Array &p_var, double p_sigma_l) {
	PackedFloat32Array res;
	const int64_t N = (int64_t)p_w * p_h;
	if (p_w < 1 || p_h < 1 || p_rgb.size() != N * 3 || p_guide.size() != N * 3) {
		return p_rgb;
	}
	static const float H[5] = { 1.0f / 16, 1.0f / 4, 3.0f / 8, 1.0f / 4, 1.0f / 16 };
	std::vector<float> a(p_rgb.ptr(), p_rgb.ptr() + N * 3), b(N * 3);
	const float *g = p_guide.ptr();
	const bool use_var = p_var.size() == N;
	std::vector<float> va, vb;
	if (use_var) {
		va.assign(p_var.ptr(), p_var.ptr() + N);
		vb.resize(N);
	}
	const float sl = (float)p_sigma_l;
	const float inv_g = (float)(1.0 / std::max(p_sigma_g * p_sigma_g, 1e-12));
	for (int it = 0; it < p_iters; it++) {
		const int step = 1 << it;
		const double sc = p_sigma_c / (double)(1 << it);
		const float inv_c = (float)(1.0 / std::max(sc * sc, 1e-12));
		auto rows = [&](int y0, int y1) {
			for (int y = y0; y < y1; y++) {
				for (int x = 0; x < p_w; x++) {
					const int64_t ci = ((int64_t)y * p_w + x) * 3;
					float sum[3] = { 0, 0, 0 };
					float wsum = 0, vsum = 0;
					for (int dy = -2; dy <= 2; dy++) {
						const int yy = y + dy * step;
						if (yy < 0 || yy >= p_h) {
							continue;
						}
						for (int dx = -2; dx <= 2; dx++) {
							const int xx = x + dx * step;
							if (xx < 0 || xx >= p_w) {
								continue;
							}
							const int64_t qi = ((int64_t)yy * p_w + xx) * 3;
							float dc = 0, dg = 0;
							for (int c = 0; c < 3; c++) {
								const float u = a[ci + c] - a[qi + c];
								const float v = g[ci + c] - g[qi + c];
								dc += u * u;
								dg += v * v;
							}
							float ec = dc * inv_c;
							if (use_var) {
								// SVGF-style: luminance difference against sigma_l * sqrt(variance of the centre) + eps
								const float dl = 0.2126f * (a[ci] - a[qi]) + 0.7152f * (a[ci + 1] - a[qi + 1]) + 0.0722f * (a[ci + 2] - a[qi + 2]);
								const float den = sl * std::sqrt(std::max(va[ci / 3], 0.0f)) + 1e-4f;
								ec = dl * dl / (den * den);
							}
							const float w = H[dx + 2] * H[dy + 2] * std::exp(-ec - dg * inv_g);
							wsum += w;
							vsum += w * w * (use_var ? va[qi / 3] : 0.0f);
							for (int c = 0; c < 3; c++) {
								sum[c] += w * a[qi + c];
							}
						}
					}
					for (int c = 0; c < 3; c++) {
						b[ci + c] = wsum > 0 ? sum[c] / wsum : a[ci + c];
					}
					if (use_var) {
						vb[ci / 3] = wsum > 0 ? vsum / (wsum * wsum) : va[ci / 3];
					}
				}
			}
		};
		unsigned hw = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
		if (N < 4096) {
			hw = 1;
		}
		std::vector<std::thread> th;
		const int per = (p_h + (int)hw - 1) / (int)hw;
		for (unsigned t = 0; t < hw; t++) {
			const int y0 = (int)t * per, y1 = std::min(p_h, y0 + per);
			if (y0 >= y1) {
				break;
			}
			if (hw == 1) {
				rows(y0, y1);
			} else {
				th.emplace_back(rows, y0, y1);
			}
		}
		for (auto &t : th) {
			t.join();
		}
		a.swap(b);
		if (use_var) {
			va.swap(vb);
		}
	}
	res.resize(N * 3);
	std::copy(a.begin(), a.end(), res.ptrw());
	return res;
}

void KineRenderNative::_bind_methods() {
	ClassDB::bind_static_method("KineRenderNative", D_METHOD("version"), &KineRenderNative::version);
	ClassDB::bind_static_method("KineRenderNative", D_METHOD("accumulate", "imgs"), &KineRenderNative::accumulate);
	ClassDB::bind_static_method("KineRenderNative", D_METHOD("denoise", "rgb", "guide", "w", "h", "iters", "sigma_c", "sigma_g", "var", "sigma_l"), &KineRenderNative::denoise);
	ClassDB::bind_static_method("KineRenderNative", D_METHOD("accumulate_var", "imgs"), &KineRenderNative::accumulate_var);
}
