extends RefCounted
## CH15: IAPWS-IF97 (R7-97(2012)) regions 1, 2 and 4, the parts of the formulation a PWR heat balance touches: compressed liquid (region 1, T <= 623.15 K,
## p >= p_sat), steam (region 2, the ideal-gas part + the residual part) and the saturation line (region 4, both directions). p in MPa, T in K,
## v m3/kg, h u kJ/kg, s cp kJ/kg K, w m/s. Coefficients from the release's tables 2, 10, 11 and 34. GDScript only: a few dozen calls per run.
const R := 0.461526   # kJ/kg K, Eq. (1)

const R1_I := [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 8, 8, 21, 23, 29, 30, 31, 32]
const R1_J := [-2, -1, 0, 1, 2, 3, 4, 5, -9, -7, -1, 0, 1, 3, -3, 0, 1, 3, 17, -4, 0, 6, -5, -2, 10, -8, -11, -6, -29, -31, -38, -39, -40, -41]
const R1_N := [0.14632971213167, -0.84548187169114, -0.37563603672040e1, 0.33855169168385e1, -0.95791963387872, 0.15772038513228, -0.16616417199501e-1,
	0.81214629983568e-3, 0.28319080123804e-3, -0.60706301565874e-3, -0.18990068218419e-1, -0.32529748770505e-1, -0.21841717175414e-1, -0.52838357969930e-4,
	-0.47184321073267e-3, -0.30001780793026e-3, 0.47661393906987e-4, -0.44141845330846e-5, -0.72694996297594e-15, -0.31679644845054e-4, -0.28270797985312e-5,
	-0.85205128120103e-9, -0.22425281908000e-5, -0.65171222895601e-6, -0.14341729937924e-12, -0.40516996860117e-6, -0.12734301741641e-8, -0.17424871230634e-9,
	-0.68762131295531e-18, 0.14478307828521e-19, 0.26335781662795e-22, -0.11947622640071e-22, 0.18228094581404e-23, -0.93537087292458e-25]

const R2_J0 := [0, 1, -5, -4, -3, -2, -1, 2, 3]
const R2_N0 := [-0.96927686500217e1, 0.10086655968018e2, -0.56087911283020e-2, 0.71452738081455e-1, -0.40710498223928, 0.14240819171444e1,
	-0.43839511319450e1, -0.28408632460772, 0.21268463753307e-1]
const R2_I := [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 5, 6, 6, 6, 7, 7, 7, 8, 8, 9, 10, 10, 10, 16, 16, 18, 20, 20, 20, 21, 22, 23, 24, 24, 24]
const R2_J := [0, 1, 2, 3, 6, 1, 2, 4, 7, 36, 0, 1, 3, 6, 35, 1, 2, 3, 7, 3, 16, 35, 0, 11, 25, 8, 36, 13, 4, 10, 14, 29, 50, 57, 20, 35, 48, 21, 53, 39, 26, 40, 58]
const R2_N := [-0.17731742473213e-2, -0.17834862292358e-1, -0.45996013696365e-1, -0.57581259083432e-1, -0.50325278727930e-1, -0.33032641670203e-4,
	-0.18948987516315e-3, -0.39392777243355e-2, -0.43797295650573e-1, -0.26674547914087e-4, 0.20481737692309e-7, 0.43870667284435e-6, -0.32277677238570e-4,
	-0.15033924542148e-2, -0.40668253562649e-1, -0.78847309559367e-9, 0.12790717852285e-7, 0.48225372718507e-6, 0.22922076337661e-5, -0.16714766451061e-10,
	-0.21171472321355e-2, -0.23895741934104e2, -0.59059564324270e-17, -0.12621808899101e-5, -0.38946842435739e-1, 0.11256211360459e-10, -0.82311340897998e1,
	0.19809712802088e-7, 0.10406965210174e-18, -0.10234747095929e-12, -0.10018179379511e-8, -0.80882908646985e-10, 0.10693031879409, -0.33662250574171,
	0.89185845355421e-24, 0.30629316876232e-12, -0.42002467698208e-5, -0.59056029685639e-25, 0.37826947613457e-5, -0.12768608934681e-14, 0.73087610595061e-28,
	0.55414715350778e-16, -0.94369707241210e-6]

const R4_N := [0.11670521452767e4, -0.72421316703206e6, -0.17073846940092e2, 0.12020824702470e5, -0.32325550322333e7, 0.14915108613530e2,
	-0.48232657361591e4, 0.40511340542057e6, -0.23855557567849, 0.65017534844798e3]


## region 1 at (p MPa, T K)
static func r1(p: float, t: float) -> Dictionary:
	var pi := p / 16.53
	var tau := 1386.0 / t
	var a := 7.1 - pi
	var b := tau - 1.222
	var g := 0.0
	var gp := 0.0
	var gt := 0.0
	var gtt := 0.0
	var gpp := 0.0
	var gpt := 0.0
	for i in R1_N.size():
		var n: float = R1_N[i]
		var ii: int = R1_I[i]
		var jj: int = R1_J[i]
		g += n * pow(a, ii) * pow(b, jj)
		gp += -n * ii * pow(a, ii - 1) * pow(b, jj)
		gpp += n * ii * (ii - 1) * pow(a, ii - 2) * pow(b, jj)
		gt += n * pow(a, ii) * jj * pow(b, jj - 1)
		gtt += n * pow(a, ii) * jj * (jj - 1) * pow(b, jj - 2)
		gpt += -n * ii * pow(a, ii - 1) * jj * pow(b, jj - 1)
	var w2 := 1000.0 * R * t * gp * gp / ((gp - tau * gpt) * (gp - tau * gpt) / (tau * tau * gtt) - gpp)
	return {"v": R * t * pi * gp / (p * 1000.0), "h": R * t * tau * gt, "u": R * t * (tau * gt - pi * gp), "s": R * (tau * gt - g), "cp": -R * tau * tau * gtt, "w": sqrt(w2)}


## region 2 at (p MPa, T K)
static func r2(p: float, t: float) -> Dictionary:
	var pi := p
	var tau := 540.0 / t
	var g0 := log(pi)
	var g0t := 0.0
	var g0tt := 0.0
	for i in R2_N0.size():
		var n: float = R2_N0[i]
		var jj: int = R2_J0[i]
		g0 += n * pow(tau, jj)
		g0t += n * jj * pow(tau, jj - 1)
		g0tt += n * jj * (jj - 1) * pow(tau, jj - 2)
	var b := tau - 0.5
	var gr := 0.0
	var grp := 0.0
	var grt := 0.0
	var grtt := 0.0
	for i in R2_N.size():
		var n: float = R2_N[i]
		var ii: int = R2_I[i]
		var jj: int = R2_J[i]
		gr += n * pow(pi, ii) * pow(b, jj)
		grp += n * ii * pow(pi, ii - 1) * pow(b, jj)
		grt += n * pow(pi, ii) * jj * pow(b, jj - 1)
		grtt += n * pow(pi, ii) * jj * (jj - 1) * pow(b, jj - 2)
	var gp := 1.0 / pi + grp
	return {"v": R * t * pi * gp / (p * 1000.0), "h": R * t * tau * (g0t + grt), "u": R * t * (tau * (g0t + grt) - pi * gp), "s": R * (tau * (g0t + grt) - (g0 + gr)), "cp": -R * tau * tau * (g0tt + grtt)}


## region 4: the saturation pressure (MPa) at T (K), Eq. (30)
static func psat(t: float) -> float:
	var n := R4_N
	var th: float = t + n[8] / (t - n[9])
	var a: float = th * th + n[0] * th + n[1]
	var b: float = n[2] * th * th + n[3] * th + n[4]
	var c: float = n[5] * th * th + n[6] * th + n[7]
	return pow(2.0 * c / (-b + sqrt(b * b - 4.0 * a * c)), 4)


## region 4: the saturation temperature (K) at p (MPa), Eq. (31)
static func tsat(p: float) -> float:
	var n := R4_N
	var be := pow(p, 0.25)
	var e: float = be * be + n[2] * be + n[5]
	var f: float = n[0] * be * be + n[3] * be + n[6]
	var g: float = n[1] * be * be + n[4] * be + n[7]
	var d: float = 2.0 * g / (-f - sqrt(f * f - 4.0 * e * g))
	return (n[9] + d - sqrt((n[9] + d) * (n[9] + d) - 4.0 * (n[8] + n[9] * d))) / 2.0
