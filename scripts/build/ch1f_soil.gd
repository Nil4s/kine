class_name Ch1fSoil
extends RefCounted
## CH1f: soil-structure interaction for the CH1 house. Gazetas (1991) closed-form impedances of a rigid rectangular surface footing on a homogeneous
## elastic half-space, site classes (ASCE 7 / NBR 15421 A-E by Vs30), expansive-clay heave, NBR 6123 wind. Sources and UNVERIFIED flags: docs/CH1f_REFERENCE.md.
## LABEL: every output and doc of CH1f is a physics model with cited typical values, NOT an NBR code check (Nick, 11-04: the ABNT texts are not owned; NBR values appear only through
## a citable secondary source or are marked UNVERIFIED). No compliance with any NBR is claimed anywhere.
## Units: N, m, kg, s. The house footprint is 9.754 x 7.620 m; x is the long side.

const LABEL := "physics model with cited typical values, NOT an NBR code check"
const LX := 9.754
const LZ := 7.620
const G_ACC := 9.80665
const FT_PER_M := 3.28084

## Representative parameters per class. vs in m/s (SI only: the ft/s of ASCE 7 Table 20.3-1 is converted by to_ms()).
## rho and nu are typical textbook values (UNVERIFIED for any real site); vs is chosen inside the class range.
const CLASSES := {
	"rock": {"asce": "B", "vs_lo": 760.0, "vs_hi": 1500.0, "vs": 1100.0, "rho": 2600.0, "nu": 0.25, "label": "rock"},
	"dense": {"asce": "C", "vs_lo": 360.0, "vs_hi": 760.0, "vs": 560.0, "rho": 2000.0, "nu": 0.30, "label": "dense soil"},
	"stiff_clay": {"asce": "D", "vs_lo": 180.0, "vs_hi": 360.0, "vs": 270.0, "rho": 1900.0, "nu": 0.40, "label": "stiff clay"},
	"soft_clay": {"asce": "E", "vs_lo": 0.0, "vs_hi": 180.0, "vs": 120.0, "rho": 1700.0, "nu": 0.45, "label": "soft clay"},
}
const ORDER := ["rock", "dense", "stiff_clay", "soft_clay"]


static func to_ms(vs_ftps: float) -> float:
	return vs_ftps / FT_PER_M


## a soil dictionary from a class id, or from explicit values {vs, rho, nu}. vs in m/s.
static func soil(id: String, vs_override := -1.0) -> Dictionary:
	var c: Dictionary = (CLASSES[id] as Dictionary).duplicate()
	if vs_override > 0.0:
		c["vs"] = vs_override
	c["id"] = id
	c["G"] = c["rho"] * c["vs"] * c["vs"]
	return c


## class letter from Vs30 (m/s): ASCE 7-16 Table 20.3-1 / NBR 15421 Table 2 boundaries (1500, 760, 360 (NBR: 370, UNVERIFIED), 180)
static func class_of(vs30: float) -> String:
	if vs30 > 1500.0:
		return "A"
	if vs30 > 760.0:
		return "B"
	if vs30 > 360.0:
		return "C"
	if vs30 >= 180.0:
		return "D"
	return "E"


## Gazetas 1991 surface foundation, rectangle of full length lx (x) and width lz (z), vertical axis y. Returns stiffness N/m and N m/rad.
## Mapping: Gazetas x = house x (long), Gazetas y = house z, Gazetas z = vertical. L, B are HALF dimensions (L >= B).
static func gazetas(s: Dictionary, lx := LX, lz := LZ) -> Dictionary:
	var G: float = s["G"]
	var nu: float = s["nu"]
	var L := 0.5 * maxf(lx, lz)
	var B := 0.5 * minf(lx, lz)
	var Ab := 4.0 * L * B
	var chi := Ab / (4.0 * L * L)
	var Kz := 2.0 * G * L / (1.0 - nu) * (0.73 + 1.54 * pow(chi, 0.75))
	var Ky := 2.0 * G * L / (2.0 - nu) * (2.0 + 2.5 * pow(chi, 0.85))
	var Kx := Ky - 0.2 / (0.75 - nu) * G * L * (1.0 - B / L)
	var Ibx := (2.0 * L) * pow(2.0 * B, 3) / 12.0     # area moment about the long axis
	var Iby := (2.0 * B) * pow(2.0 * L, 3) / 12.0     # about the short axis
	var Krx := G / (1.0 - nu) * pow(Ibx, 0.75) * pow(L / B, 0.25) * (2.4 + 0.5 * B / L)
	var Kry := G / (1.0 - nu) * pow(Iby, 0.75) * (3.0 * pow(L / B, 0.15))
	var Jb := Ibx + Iby
	var Kt := G * pow(Jb, 0.75) * (4.0 + 11.0 * pow(1.0 - B / L, 10))
	# house axes: x long (Gazetas x), z across (Gazetas y), y vertical
	# rocking about the HOUSE x axis (tilts the house in the z-y plane, across the short side) = Gazetas rx; about the house z axis = Gazetas ry
	var out := {"kx": Kx, "ky": Kz, "kz": Ky, "rx": Krx, "ry": Kt, "rz": Kry, "L": L, "B": B, "A": Ab, "Ibx": Ibx, "Iby": Iby, "J": Jb}
	if lz > lx:   # footprint longer in z: swap roles
		out["kx"] = Ky
		out["kz"] = Kx
		out["rx"] = Kry
		out["rz"] = Krx
	# cone-model radiation dashpots (Wolf 1994; Lysmer analog, frequency independent, UNVERIFIED textbook form)
	var rho: float = s["rho"]
	var vs: float = s["vs"]
	var vla := 3.4 * vs / (PI * (1.0 - nu))
	out["cx"] = rho * vs * Ab
	out["cy"] = rho * vla * Ab
	out["cz"] = rho * vs * Ab
	out["crx"] = rho * vla * Ibx
	out["cry"] = rho * vs * Jb
	out["crz"] = rho * vla * Iby
	return out


## Veletsos-Meek 1974 period lengthening of a single-DOF structure (stiffness k, height h) on a rigid footing with horizontal Kx and rocking Kth:
## T~/T = sqrt(1 + k/Kx + k h^2 / Kth)
static func veletsos_ratio(k: float, h: float, Kx: float, Kth: float) -> float:
	return sqrt(1.0 + k / Kx + k * h * h / Kth)


## dof index helper: node * 6 + d
static func dofk_for(g: Dictionary, f: int) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.append_array([f * 6 + 0, g["kx"], f * 6 + 1, g["ky"], f * 6 + 2, g["kz"], f * 6 + 3, g["rx"], f * 6 + 4, g["ry"], f * 6 + 5, g["rz"]])
	return o


static func dofc_for(g: Dictionary, f: int) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.append_array([f * 6 + 0, g["cx"], f * 6 + 1, g["cy"], f * 6 + 2, g["cz"], f * 6 + 3, g["crx"], f * 6 + 4, g["cry"], f * 6 + 5, g["crz"]])
	return o


# ------------------------------------------------------------------------------------------------ expansive clay heave
## Free-field heave: active depth * free swell strain (UNVERIFIED for cerrado clays, see the reference), reduced by the building pressure q over the
## swell pressure ps: dh = h_act * eps * max(0, 1 - q / ps). All inputs explicit so the table states them.
const H_ACTIVE := 1.5       # m, depth of seasonal moisture change (UNVERIFIED)
const EPS_FREE := 0.02      # free swell strain (UNVERIFIED)
const P_SWELL := 100.0e3    # Pa, within the 28..162 kPa range of Brazilian expansive soils quoted in the literature (see the reference); not a Cuiabá measurement


static func heave_free(q_pa: float, h_act := H_ACTIVE, eps := EPS_FREE, ps := P_SWELL) -> float:
	return h_act * eps * maxf(0.0, 1.0 - q_pa / ps)


## centre-lift mound (edges dried and shrunk, centre swelling) as vertical ground displacement at plan point (x, z): sin x sin bowl, 0 at the edges, dh at the middle
static func mound(x: float, z: float, dh: float, lx := LX, lz := LZ) -> float:
	return dh * sin(PI * x / lx) * sin(PI * z / lz)


# ------------------------------------------------------------------------------------------------ wind, NBR 6123:1988
const V0_CUIABA := 35.0     # m/s basic wind speed (3 s gust, 50 yr, 10 m), isopleth map Fig. 1 read for Cuiaba: UNVERIFIED (not read from the map)
const CE_WIND := 0.7        # windward wall, NBR 6123 Table 4 (a/b 1..1.5, h/b <= 1/2): UNVERIFIED
const CE_LEE := -0.5        # leeward wall: UNVERIFIED


## NBR 6123: Vk = V0 S1 S2 S3, q = 0.613 Vk^2 (N/m2). S2 = b Fr (z/10)^p; category III (suburbs, scattered obstacles), class A: b 0.94, Fr 1.0, p 0.105 (UNVERIFIED table values)
static func wind(z_m := 3.2, v0 := V0_CUIABA, s1 := 1.0, s3 := 1.0) -> Dictionary:
	var s2 := 0.94 * 1.0 * pow(maxf(z_m, 5.0) / 10.0, 0.105)   # S2 table starts at z = 5 m
	var vk := v0 * s1 * s2 * s3
	var q := 0.613 * vk * vk
	return {"S2": s2, "vk": vk, "q": q, "p_net": q * (CE_WIND - CE_LEE)}
