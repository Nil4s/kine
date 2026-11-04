#include <cstdlib>
#include "kine_cad.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <BRepAdaptor_Surface.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepFilletAPI_MakeChamfer.hxx>
#include <BRepGProp_Face.hxx>
#include <BRepOffsetAPI_MakePipe.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepTools.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRep_Builder.hxx>
#include <TopoDS_Shell.hxx>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <BRepLib.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <GC_MakeArcOfCircle.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <Geom_Curve.hxx>
#include <Geom_Surface.hxx>
#include <LocOpe_DPrism.hxx>
#include <ShapeFix_Face.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <gp_Circ.hxx>
#include <gp_Mat.hxx>
#include <gp_Pln.hxx>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <cmath>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepGProp.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepOffsetAPI_MakeThickSolid.hxx>
#include <BRepOffsetAPI_MakeOffsetShape.hxx>
#include <GeomAbs_JoinType.hxx>
#include <BRepOffsetAPI_DraftAngle.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakeSphere.hxx>
#include <BRep_Tool.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Interface_Static.hxx>
#include <NCollection_List.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <Standard_Failure.hxx>
#include <Standard_Version.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Ax1.hxx>
#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#include <fstream>
#include <map>
#include <mutex>
#include <string>

using namespace godot;

namespace {
std::mutex g_mu;
std::map<int, TopoDS_Shape> g_shapes;
int g_next = 1;
std::string g_err;

int kc_put(const TopoDS_Shape &s) {
	if (s.IsNull()) {
		g_err = "the operation produced an empty shape";
		return 0;
	}
	std::lock_guard<std::mutex> lk(g_mu);
	int id = g_next++;
	g_shapes[id] = s;
	return id;
}

bool kc_get(int id, TopoDS_Shape &out) {
	std::lock_guard<std::mutex> lk(g_mu);
	auto it = g_shapes.find(id);
	if (it == g_shapes.end()) {
		g_err = "no such shape id";
		return false;
	}
	out = it->second;
	return true;
}

void fail(const char *what, const Standard_Failure &e) {
	const char *m = e.GetMessageString();
	g_err = std::string(what) + ": " + (m && *m ? m : "OCCT failure");
}

int count_of(int id, TopAbs_ShapeEnum t) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return -1;
	}
	TopTools_IndexedMapOfShape m;
	TopExp::MapShapes(s, t, m);
	return m.Extent();
}
} // namespace

#define KCAD_TRY try {
#define KCAD_CATCH(name, ret) \
	} \
	catch (const Standard_Failure &e) { \
		fail(name, e); \
		return ret; \
	}

void KineCAD::_bind_methods() {
	ClassDB::bind_static_method("KineCAD", D_METHOD("version"), &KineCAD::version);
	ClassDB::bind_static_method("KineCAD", D_METHOD("occt_version"), &KineCAD::occt_version);
	ClassDB::bind_static_method("KineCAD", D_METHOD("last_error"), &KineCAD::last_error);
	ClassDB::bind_static_method("KineCAD", D_METHOD("box", "dx", "dy", "dz"), &KineCAD::box);
	ClassDB::bind_static_method("KineCAD", D_METHOD("cylinder", "r", "h"), &KineCAD::cylinder);
	ClassDB::bind_static_method("KineCAD", D_METHOD("sphere", "r"), &KineCAD::sphere);
	ClassDB::bind_static_method("KineCAD", D_METHOD("translate", "id", "by"), &KineCAD::translate);
	ClassDB::bind_static_method("KineCAD", D_METHOD("rotate", "id", "axis", "radians"), &KineCAD::rotate);
	ClassDB::bind_static_method("KineCAD", D_METHOD("union", "a", "b"), &KineCAD::union_);
	ClassDB::bind_static_method("KineCAD", D_METHOD("cut", "a", "b"), &KineCAD::cut);
	ClassDB::bind_static_method("KineCAD", D_METHOD("intersect", "a", "b"), &KineCAD::intersect);
	ClassDB::bind_static_method("KineCAD", D_METHOD("fillet_all", "id", "radius"), &KineCAD::fillet_all);
	ClassDB::bind_static_method("KineCAD", D_METHOD("shell", "id", "thickness", "open_dir"), &KineCAD::shell);
	ClassDB::bind_static_method("KineCAD", D_METHOD("volume", "id"), &KineCAD::volume);
	ClassDB::bind_static_method("KineCAD", D_METHOD("area", "id"), &KineCAD::area);
	ClassDB::bind_static_method("KineCAD", D_METHOD("face_count", "id"), &KineCAD::face_count);
	ClassDB::bind_static_method("KineCAD", D_METHOD("edge_count", "id"), &KineCAD::edge_count);
	ClassDB::bind_static_method("KineCAD", D_METHOD("tessellate", "id", "deflection", "angle"), &KineCAD::tessellate);
	ClassDB::bind_static_method("KineCAD", D_METHOD("export_step", "id", "path"), &KineCAD::export_step);
	ClassDB::bind_static_method("KineCAD", D_METHOD("import_step", "path"), &KineCAD::import_step);
	ClassDB::bind_static_method("KineCAD", D_METHOD("sketch_wire", "items", "origin", "x_dir", "normal"), &KineCAD::sketch_wire);
	ClassDB::bind_static_method("KineCAD", D_METHOD("sketch_face", "items", "origin", "x_dir", "normal"), &KineCAD::sketch_face);
	ClassDB::bind_static_method("KineCAD", D_METHOD("path_wire", "points"), &KineCAD::path_wire);
	ClassDB::bind_static_method("KineCAD", D_METHOD("face_from_wire", "wire"), &KineCAD::face_from_wire);
	ClassDB::bind_static_method("KineCAD", D_METHOD("extrude", "face", "dist", "both", "taper"), &KineCAD::extrude);
	ClassDB::bind_static_method("KineCAD", D_METHOD("revolve", "profile", "axis_origin", "axis_dir", "radians"), &KineCAD::revolve);
	ClassDB::bind_static_method("KineCAD", D_METHOD("sweep", "profile", "path"), &KineCAD::sweep);
	ClassDB::bind_static_method("KineCAD", D_METHOD("loft", "profiles", "ruled", "solid"), &KineCAD::loft);
	ClassDB::bind_static_method("KineCAD", D_METHOD("solid_from_mesh", "verts", "tris", "tol"), &KineCAD::solid_from_mesh);
	ClassDB::bind_static_method("KineCAD", D_METHOD("offset", "id", "distance"), &KineCAD::offset);
	ClassDB::bind_static_method("KineCAD", D_METHOD("edges", "id"), &KineCAD::edges);
	ClassDB::bind_static_method("KineCAD", D_METHOD("faces", "id"), &KineCAD::faces);
	ClassDB::bind_static_method("KineCAD", D_METHOD("fillet_edges", "id", "edge_ids", "radius"), &KineCAD::fillet_edges);
	ClassDB::bind_static_method("KineCAD", D_METHOD("chamfer_edges", "id", "edge_ids", "dist"), &KineCAD::chamfer_edges);
	ClassDB::bind_static_method("KineCAD", D_METHOD("offset_face", "id", "face_id", "dist"), &KineCAD::offset_face);
	ClassDB::bind_static_method("KineCAD", D_METHOD("draft_faces", "id", "face_ids", "angle", "pull_dir", "neutral_origin"), &KineCAD::draft_faces);
	ClassDB::bind_static_method("KineCAD", D_METHOD("mirror", "id", "origin", "normal"), &KineCAD::mirror);
	ClassDB::bind_static_method("KineCAD", D_METHOD("pattern_linear", "id", "step", "count"), &KineCAD::pattern_linear);
	ClassDB::bind_static_method("KineCAD", D_METHOD("pattern_circular", "id", "axis_origin", "axis_dir", "count", "total_radians"), &KineCAD::pattern_circular);
	ClassDB::bind_static_method("KineCAD", D_METHOD("mass_properties", "id"), &KineCAD::mass_properties);
	ClassDB::bind_static_method("KineCAD", D_METHOD("release", "id"), &KineCAD::release);
	ClassDB::bind_static_method("KineCAD", D_METHOD("release_all"), &KineCAD::release_all);
	ClassDB::bind_static_method("KineCAD", D_METHOD("live_count"), &KineCAD::live_count);
}

int KineCAD::version() {
	return 5;
}
String KineCAD::occt_version() {
	return String(OCC_VERSION_COMPLETE);
}
String KineCAD::last_error() {
	return String::utf8(g_err.c_str());
}

int KineCAD::box(double dx, double dy, double dz) {
	KCAD_TRY
	BRepPrimAPI_MakeBox mk(gp_Pnt(-dx / 2, -dy / 2, -dz / 2), dx, dy, dz);
	return kc_put(mk.Shape());
	KCAD_CATCH("box", 0)
}

int KineCAD::cylinder(double r, double h) {
	KCAD_TRY
	BRepPrimAPI_MakeCylinder mk(gp_Ax2(gp_Pnt(0, 0, -h / 2), gp_Dir(0, 0, 1)), r, h);
	return kc_put(mk.Shape());
	KCAD_CATCH("cylinder", 0)
}

int KineCAD::sphere(double r) {
	KCAD_TRY
	BRepPrimAPI_MakeSphere mk(gp_Pnt(0, 0, 0), r);
	return kc_put(mk.Shape());
	KCAD_CATCH("sphere", 0)
}

int KineCAD::translate(int id, const Vector3 &by) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	KCAD_TRY
	gp_Trsf t;
	t.SetTranslation(gp_Vec(by.x, by.y, by.z));
	BRepBuilderAPI_Transform tr(s, t, true);
	return kc_put(tr.Shape());
	KCAD_CATCH("translate", 0)
}

int KineCAD::rotate(int id, const Vector3 &axis, double radians) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	KCAD_TRY
	gp_Trsf t;
	t.SetRotation(gp_Ax1(gp_Pnt(0, 0, 0), gp_Dir(axis.x, axis.y, axis.z)), radians);
	BRepBuilderAPI_Transform tr(s, t, true);
	return kc_put(tr.Shape());
	KCAD_CATCH("rotate", 0)
}

int KineCAD::union_(int a, int b) {
	TopoDS_Shape sa, sb;
	if (!kc_get(a, sa) || !kc_get(b, sb)) {
		return 0;
	}
	KCAD_TRY
	BRepAlgoAPI_Fuse op(sa, sb);
	if (!op.IsDone() || op.HasErrors()) {
		g_err = "union failed";
		return 0;
	}
	return kc_put(op.Shape());
	KCAD_CATCH("union", 0)
}

int KineCAD::cut(int a, int b) {
	TopoDS_Shape sa, sb;
	if (!kc_get(a, sa) || !kc_get(b, sb)) {
		return 0;
	}
	KCAD_TRY
	BRepAlgoAPI_Cut op(sa, sb);
	if (!op.IsDone() || op.HasErrors()) {
		g_err = "cut failed";
		return 0;
	}
	return kc_put(op.Shape());
	KCAD_CATCH("cut", 0)
}

int KineCAD::intersect(int a, int b) {
	TopoDS_Shape sa, sb;
	if (!kc_get(a, sa) || !kc_get(b, sb)) {
		return 0;
	}
	KCAD_TRY
	BRepAlgoAPI_Common op(sa, sb);
	if (!op.IsDone() || op.HasErrors()) {
		g_err = "intersect failed";
		return 0;
	}
	return kc_put(op.Shape());
	KCAD_CATCH("intersect", 0)
}

int KineCAD::fillet_all(int id, double radius) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	KCAD_TRY
	BRepFilletAPI_MakeFillet mk(s);
	TopTools_IndexedMapOfShape edges;
	TopExp::MapShapes(s, TopAbs_EDGE, edges);
	for (int i = 1; i <= edges.Extent(); i++) {
		mk.Add(radius, TopoDS::Edge(edges(i)));
	}
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "fillet failed (radius too large for an edge?)";
		return 0;
	}
	return kc_put(mk.Shape());
	KCAD_CATCH("fillet_all", 0)
}

int KineCAD::shell(int id, double thickness, const Vector3 &open_dir) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	KCAD_TRY
	NCollection_List<TopoDS_Shape> closing;
	if (open_dir.length_squared() > 1e-12) {
		Vector3 want = open_dir.normalized();
		double best = 0.5;
		TopoDS_Face pick;
		for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
			TopoDS_Face f = TopoDS::Face(ex.Current());
			BRepAdaptor_Surface sf(f);
			if (sf.GetType() != GeomAbs_Plane) {
				continue;
			}
			gp_Dir n = sf.Plane().Axis().Direction();
			if (f.Orientation() == TopAbs_REVERSED) {
				n.Reverse();
			}
			double d = n.X() * want.x + n.Y() * want.y + n.Z() * want.z;
			if (d > best) {
				best = d;
				pick = f;
			}
		}
		if (pick.IsNull()) {
			g_err = "shell: no planar face points that way";
			return 0;
		}
		closing.Append(pick);
	}
	BRepOffsetAPI_MakeThickSolid mk;
	mk.MakeThickSolidByJoin(s, closing, -thickness, 1e-4);
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "shell failed (thickness too large?)";
		return 0;
	}
	if (closing.IsEmpty()) {
		// with no face to open, MakeThickSolid returns only the inward offset body: the hollow part is the shape minus that
		BRepAlgoAPI_Cut cut(s, mk.Shape());
		if (!cut.IsDone() || cut.HasErrors()) {
			g_err = "shell: could not cut the cavity";
			return 0;
		}
		return kc_put(cut.Shape());
	}
	return kc_put(mk.Shape());
	KCAD_CATCH("shell", 0)
}

double KineCAD::volume(int id) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return -1.0;
	}
	KCAD_TRY
	GProp_GProps p;
	BRepGProp::VolumePropertiesGK(s, p, 1e-9, false, true); // Gauss-Kronrod per knot span: the fixed Gauss rule is 0.3% off on a B-spline wall
	return p.Mass();
	KCAD_CATCH("volume", -1.0)
}

double KineCAD::area(int id) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return -1.0;
	}
	KCAD_TRY
	GProp_GProps p;
	BRepGProp::SurfaceProperties(s, p, 1e-9);
	return p.Mass();
	KCAD_CATCH("area", -1.0)
}

int KineCAD::face_count(int id) {
	return count_of(id, TopAbs_FACE);
}
int KineCAD::edge_count(int id) {
	return count_of(id, TopAbs_EDGE);
}

Ref<ArrayMesh> KineCAD::tessellate(int id, double deflection, double angle) {
	Ref<ArrayMesh> mesh;
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return mesh;
	}
	KCAD_TRY
	BRepMesh_IncrementalMesh inc(s, deflection, false, angle, true); // s249n: faces meshed in parallel (same triangulation, a few cores)
	PackedVector3Array verts, norms;
	PackedInt32Array idx;
	for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
		TopoDS_Face f = TopoDS::Face(ex.Current());
		TopLoc_Location loc;
		Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(f, loc);
		if (tri.IsNull()) {
			continue;
		}
		BRepLib_ToolTriangulatedShape::ComputeNormals(f, tri);
		const bool rev = f.Orientation() == TopAbs_REVERSED;
		const int base = verts.size();
		const int nn = tri->NbNodes();
		for (int i = 1; i <= nn; i++) {
			gp_Pnt p = tri->Node(i).Transformed(loc.Transformation());
			verts.push_back(Vector3(p.X(), p.Y(), p.Z()));
			if (tri->HasNormals()) {
				gp_Dir n = tri->Normal(i).Transformed(loc.Transformation());
				if (rev) {
					n.Reverse();
				}
				norms.push_back(Vector3(n.X(), n.Y(), n.Z()));
			} else {
				norms.push_back(Vector3(0, 1, 0));
			}
		}
		for (int i = 1; i <= tri->NbTriangles(); i++) {
			int a, b, c;
			tri->Triangle(i).Get(a, b, c);
			if (!rev) {
				std::swap(b, c); // Godot's front face is clockwise; OCCT's outward triangles are counter-clockwise
			}
			idx.push_back(base + a - 1);
			idx.push_back(base + b - 1);
			idx.push_back(base + c - 1);
		}
	}
	if (idx.is_empty()) {
		g_err = "tessellate: no triangles";
		return mesh;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_NORMAL] = norms;
	arrays[Mesh::ARRAY_INDEX] = idx;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
	KCAD_CATCH("tessellate", Ref<ArrayMesh>())
}

bool KineCAD::export_step(int id, const String &path) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return false;
	}
	KCAD_TRY
	STEPControl_Writer w;
	if (w.Transfer(s, STEPControl_AsIs) != IFSelect_RetDone) {
		g_err = "export_step: transfer failed";
		return false;
	}
	if (w.Write(path.utf8().get_data()) != IFSelect_RetDone) {
		g_err = "export_step: could not write the file";
		return false;
	}
	return true;
	KCAD_CATCH("export_step", false)
}

int KineCAD::import_step(const String &path) {
	KCAD_TRY
	{
		// OCCT's reader dies outright on a missing file in this build (no exception to catch): look first
		std::ifstream probe(path.utf8().get_data(), std::ios::binary);
		if (!probe.good()) {
			g_err = "import_step: no such file";
			return 0;
		}
	}
	STEPControl_Reader r;
	if (r.ReadFile(path.utf8().get_data()) != IFSelect_RetDone) {
		g_err = "import_step: could not read the file";
		return 0;
	}
	if (r.TransferRoots() <= 0) {
		g_err = "import_step: nothing to transfer";
		return 0;
	}
	return kc_put(r.OneShape());
	KCAD_CATCH("import_step", 0)
}

// ------------------------------------------------------------------ phase 2: sketch -> solid
namespace {
struct Frame {
	gp_Pnt o;
	gp_Dir x, y, n;
	gp_Pnt at(const Vector2 &p) const {
		return gp_Pnt(o.X() + p.x * x.X() + p.y * y.X(), o.Y() + p.x * x.Y() + p.y * y.Y(), o.Z() + p.x * x.Z() + p.y * y.Z());
	}
};

bool make_frame(const Vector3 &origin, const Vector3 &xd, const Vector3 &nd, Frame &f) {
	if (nd.length_squared() < 1e-18 || xd.length_squared() < 1e-18) {
		g_err = "sketch plane: x_dir and normal must be non-zero";
		return false;
	}
	gp_Dir n(nd.x, nd.y, nd.z);
	gp_Vec xv(xd.x, xd.y, xd.z);
	xv -= gp_Vec(n) * xv.Dot(gp_Vec(n)); // x made perpendicular to n
	if (xv.Magnitude() < 1e-9) {
		g_err = "sketch plane: x_dir is parallel to the normal";
		return false;
	}
	f.o = gp_Pnt(origin.x, origin.y, origin.z);
	f.n = n;
	f.x = gp_Dir(xv);
	f.y = n.Crossed(f.x);
	return true;
}

bool shape_normal(const TopoDS_Face &f, gp_Dir &n) {
	BRepAdaptor_Surface sf(f);
	if (sf.GetType() != GeomAbs_Plane) {
		g_err = "extrude needs a planar face";
		return false;
	}
	n = sf.Plane().Axis().Direction();
	if (f.Orientation() == TopAbs_REVERSED) {
		n.Reverse();
	}
	return true;
}

TopoDS_Shape fuse_all(const TopoDS_Shape &a, const TopoDS_Shape &b) {
	BRepAlgoAPI_Fuse op(a, b);
	if (!op.IsDone() || op.HasErrors()) {
		return TopoDS_Shape();
	}
	return op.Shape();
}

// a solid built against its own orientation reports a negative volume: flip it so volumes are always positive
TopoDS_Shape outward(const TopoDS_Shape &s) {
	if (s.IsNull()) {
		return s;
	}
	GProp_GProps p;
	BRepGProp::VolumeProperties(s, p);
	return p.Mass() < 0.0 ? s.Reversed() : s;
}

int kc_put_solid(const TopoDS_Shape &s) {
	if (s.IsNull()) {
		g_err = "the operation produced an empty shape";
		return 0;
	}
	return kc_put(outward(s));
}

Vector3 v3(const gp_Pnt &p) {
	return Vector3(p.X(), p.Y(), p.Z());
}

// the closed wire of a sketch, built straight from the item list
bool build_wire(const Array &items, const Frame &fr, TopoDS_Wire &out) {
	NCollection_List<TopoDS_Shape> edges;
	for (int i = 0; i < items.size(); i++) {
		Dictionary d = items[i];
		String t = d.get("t", "");
		if (t == "line") {
			BRepBuilderAPI_MakeEdge me(fr.at(d["a"]), fr.at(d["b"]));
			if (!me.IsDone()) {
				g_err = "sketch: a zero-length line";
				return false;
			}
			edges.Append(me.Edge());
		} else if (t == "arc") {
			GC_MakeArcOfCircle arc(fr.at(d["a"]), fr.at(d["m"]), fr.at(d["b"]));
			if (!arc.IsDone()) {
				g_err = "sketch: the three arc points are collinear";
				return false;
			}
			edges.Append(BRepBuilderAPI_MakeEdge(arc.Value()).Edge());
		} else if (t == "circle") {
			double r = d["r"];
			if (r <= 0.0) {
				g_err = "sketch: circle radius must be > 0";
				return false;
			}
			gp_Circ c(gp_Ax2(fr.at(d["c"]), fr.n, fr.x), r);
			edges.Append(BRepBuilderAPI_MakeEdge(c).Edge());
		} else if (t == "bspline") {
			PackedVector2Array pts = d["pts"];
			bool closed = d.get("closed", false);
			int n = pts.size();
			if (closed && n > 2 && pts[0].distance_to(pts[n - 1]) < 1e-9) {
				n--; // the periodic fit closes itself: drop a repeated last point
			}
			if (n < 2 || (closed && n < 3)) {
				g_err = "sketch: a B-spline needs 2 points (3 when closed)";
				return false;
			}
			Handle(TColgp_HArray1OfPnt) arr = new TColgp_HArray1OfPnt(1, n);
			for (int k = 0; k < n; k++) {
				arr->SetValue(k + 1, fr.at(pts[k]));
			}
			GeomAPI_Interpolate fit(arr, closed, 1e-7);
			fit.Perform();
			if (!fit.IsDone()) {
				g_err = "sketch: the B-spline fit failed (repeated points?)";
				return false;
			}
			edges.Append(BRepBuilderAPI_MakeEdge(fit.Curve()).Edge());
		} else {
			g_err = std::string("sketch: unknown item type '") + t.utf8().get_data() + "'";
			return false;
		}
	}
	if (edges.IsEmpty()) {
		g_err = "sketch: no items";
		return false;
	}
	BRepBuilderAPI_MakeWire mw;
	mw.Add(edges);
	if (!mw.IsDone()) {
		g_err = "sketch: the items do not join into one connected wire";
		return false;
	}
	out = mw.Wire();
	return true;
}

// a planar face on the plane (n, o) whatever the wire's winding; ShapeFix makes the loop the face boundary, not a hole in the plane
bool face_on_plane(const TopoDS_Wire &w, const gp_Pln &pln, TopoDS_Shape &out) {
	if (!BRep_Tool::IsClosed(w)) {
		g_err = "the loop is not closed";
		return false;
	}
	BRepBuilderAPI_MakeFace mf(pln, w, true);
	if (!mf.IsDone()) {
		g_err = "the loop is not closed";
		return false;
	}
	ShapeFix_Face fix(mf.Face());
	fix.FixOrientation();
	fix.Perform();
	out = fix.Face();
	return true;
}
} // namespace

int KineCAD::sketch_wire(const Array &items, const Vector3 &origin, const Vector3 &xd, const Vector3 &nd) {
	Frame fr;
	if (!make_frame(origin, xd, nd, fr)) {
		return 0;
	}
	KCAD_TRY
	TopoDS_Wire w;
	if (!build_wire(items, fr, w)) {
		return 0;
	}
	return kc_put(w);
	KCAD_CATCH("sketch_wire", 0)
}

int KineCAD::sketch_face(const Array &items, const Vector3 &origin, const Vector3 &xd, const Vector3 &nd) {
	Frame fr;
	if (!make_frame(origin, xd, nd, fr)) {
		return 0;
	}
	KCAD_TRY
	TopoDS_Wire w;
	if (!build_wire(items, fr, w)) {
		return 0;
	}
	TopoDS_Shape f;
	if (!face_on_plane(w, gp_Pln(fr.o, fr.n), f)) {
		g_err = "sketch_face: " + g_err;
		return 0;
	}
	return kc_put(f);
	KCAD_CATCH("sketch_face", 0)
}

int KineCAD::face_from_wire(int wid) {
	TopoDS_Shape w;
	if (!kc_get(wid, w)) {
		return 0;
	}
	if (w.ShapeType() != TopAbs_WIRE) {
		g_err = "face_from_wire: not a wire";
		return 0;
	}
	KCAD_TRY
	BRepBuilderAPI_MakeFace mf(TopoDS::Wire(w), true);
	if (!mf.IsDone()) {
		g_err = "face_from_wire: the wire is open or not planar";
		return 0;
	}
	TopoDS_Shape f;
	BRepAdaptor_Surface sf(mf.Face());
	if (!face_on_plane(TopoDS::Wire(w), sf.Plane(), f)) {
		return 0;
	}
	return kc_put(f);
	KCAD_CATCH("face_from_wire", 0)
}

int KineCAD::path_wire(const PackedVector3Array &pts) {
	if (pts.size() < 2) {
		g_err = "path_wire: needs 2 points";
		return 0;
	}
	KCAD_TRY
	BRepBuilderAPI_MakeWire mw;
	for (int i = 0; i + 1 < pts.size(); i++) {
		BRepBuilderAPI_MakeEdge me(gp_Pnt(pts[i].x, pts[i].y, pts[i].z), gp_Pnt(pts[i + 1].x, pts[i + 1].y, pts[i + 1].z));
		if (!me.IsDone()) {
			g_err = "path_wire: repeated point";
			return 0;
		}
		mw.Add(me.Edge());
	}
	if (!mw.IsDone()) {
		g_err = "path_wire: failed";
		return 0;
	}
	return kc_put(mw.Wire());
	KCAD_CATCH("path_wire", 0)
}

int KineCAD::extrude(int fid, double dist, bool both, double taper) {
	TopoDS_Shape s;
	if (!kc_get(fid, s)) {
		return 0;
	}
	if (s.ShapeType() != TopAbs_FACE) {
		g_err = "extrude: needs a face (use sketch_face / face_from_wire)";
		return 0;
	}
	if (std::fabs(dist) < 1e-12) {
		g_err = "extrude: zero distance";
		return 0;
	}
	KCAD_TRY
	TopoDS_Face face = TopoDS::Face(s);
	gp_Dir n;
	if (!shape_normal(face, n)) {
		return 0;
	}
	const gp_Vec nv(n);
	// a negative distance shifts the start face back instead of extruding against the normal
	const double len = std::fabs(dist);
	double start = dist < 0 ? -len : 0.0;
	if (both) {
		start = -len / 2.0;
	}
	TopoDS_Shape base = face;
	if (start != 0.0) {
		gp_Trsf t;
		t.SetTranslation(nv * start);
		base = BRepBuilderAPI_Transform(face, t, true).Shape();
	}
	if (std::fabs(taper) < 1e-12) {
		BRepPrimAPI_MakePrism mk(base, nv * len);
		return kc_put_solid(mk.Shape());
	}
	// tapered: LocOpe_DPrism grows the face along its normal (always, whatever the face orientation) and measures its height along the
	// slanted wall, so ask for len / cos(taper) to get a true height of len. Positive taper narrows.
	const double c = std::cos(taper);
	if (c < 0.05) {
		g_err = "extrude: taper angle too steep";
		return 0;
	}
	if (!both) {
		LocOpe_DPrism dp(TopoDS::Face(base), len / c, taper);
		return kc_put_solid(dp.Shape());
	}
	// symmetric: the upper half, and its mirror image through the sketch plane for the lower half
	LocOpe_DPrism up(face, len / 2.0 / c, taper);
	TopoDS_Shape u = outward(up.Shape());
	if (u.IsNull()) {
		g_err = "extrude: the taper is too steep for this distance";
		return 0;
	}
	gp_Trsf mt;
	mt.SetMirror(gp_Ax2(BRepAdaptor_Surface(face).Plane().Location(), n));
	TopoDS_Shape d = outward(BRepBuilderAPI_Transform(u, mt, true).Shape());
	return kc_put_solid(fuse_all(u, d));
	KCAD_CATCH("extrude", 0)
}

int KineCAD::revolve(int pid, const Vector3 &ao, const Vector3 &ad, double radians) {
	TopoDS_Shape s;
	if (!kc_get(pid, s)) {
		return 0;
	}
	if (ad.length_squared() < 1e-18) {
		g_err = "revolve: zero axis";
		return 0;
	}
	KCAD_TRY
	gp_Ax1 ax(gp_Pnt(ao.x, ao.y, ao.z), gp_Dir(ad.x, ad.y, ad.z));
	TopoDS_Shape r;
	if (std::fabs(radians) >= 2.0 * M_PI - 1e-9) {
		BRepPrimAPI_MakeRevol mk(s, ax);
		r = mk.Shape();
	} else {
		BRepPrimAPI_MakeRevol mk(s, ax, radians);
		r = mk.Shape();
	}
	return s.ShapeType() == TopAbs_FACE ? kc_put_solid(r) : kc_put(r);
	KCAD_CATCH("revolve", 0)
}

int KineCAD::sweep(int pid, int path) {
	TopoDS_Shape prof, sp;
	if (!kc_get(pid, prof) || !kc_get(path, sp)) {
		return 0;
	}
	if (sp.ShapeType() != TopAbs_WIRE) {
		g_err = "sweep: the path must be a wire";
		return 0;
	}
	KCAD_TRY
	BRepOffsetAPI_MakePipe mk(TopoDS::Wire(sp), prof);
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "sweep failed";
		return 0;
	}
	return prof.ShapeType() == TopAbs_FACE ? kc_put_solid(mk.Shape()) : kc_put(mk.Shape());
	KCAD_CATCH("sweep", 0)
}

int KineCAD::loft(const PackedInt32Array &ids, bool ruled, bool solid) {
	if (ids.size() < 2) {
		g_err = "loft: needs at least 2 profiles";
		return 0;
	}
	KCAD_TRY
	BRepOffsetAPI_ThruSections mk(solid, ruled);
	for (int i = 0; i < ids.size(); i++) {
		TopoDS_Shape s;
		if (!kc_get(ids[i], s)) {
			return 0;
		}
		if (s.ShapeType() == TopAbs_FACE) {
			mk.AddWire(BRepTools::OuterWire(TopoDS::Face(s)));
		} else if (s.ShapeType() == TopAbs_WIRE) {
			mk.AddWire(TopoDS::Wire(s));
		} else {
			g_err = "loft: profiles must be wires or faces";
			return 0;
		}
	}
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "loft failed";
		return 0;
	}
	return solid ? kc_put_solid(mk.Shape()) : kc_put(mk.Shape());
	KCAD_CATCH("loft", 0)
}

Array KineCAD::edges(int id) {
	Array out;
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return out;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape em, fm;
	TopExp::MapShapes(s, TopAbs_EDGE, em);
	TopExp::MapShapes(s, TopAbs_FACE, fm);
	TopTools_IndexedDataMapOfShapeListOfShape anc;
	TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE, anc);
	for (int i = 1; i <= em.Extent(); i++) {
		TopoDS_Edge e = TopoDS::Edge(em(i));
		BRepAdaptor_Curve c(e);
		double a = c.FirstParameter(), b = c.LastParameter();
		gp_Pnt pm;
		gp_Vec tg;
		c.D1((a + b) / 2.0, pm, tg);
		if (tg.Magnitude() > 1e-12) {
			tg.Normalize();
		}
		GProp_GProps lp;
		BRepGProp::LinearProperties(e, lp);
		Dictionary d;
		d["id"] = i;
		d["center"] = v3(pm);
		d["a"] = v3(c.Value(a));
		d["b"] = v3(c.Value(b));
		d["length"] = lp.Mass();
		d["dir"] = Vector3(tg.X(), tg.Y(), tg.Z());
		PackedInt32Array fl;
		int ai = anc.FindIndex(e);
		if (ai > 0) {
			for (const TopoDS_Shape &f : anc(ai)) {
				fl.push_back(fm.FindIndex(f));
			}
		}
		d["faces"] = fl;
		out.push_back(d);
	}
	return out;
	KCAD_CATCH("edges", Array())
}

Array KineCAD::faces(int id) {
	Array out;
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return out;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape fm;
	TopExp::MapShapes(s, TopAbs_FACE, fm);
	for (int i = 1; i <= fm.Extent(); i++) {
		TopoDS_Face f = TopoDS::Face(fm(i));
		GProp_GProps sp;
		BRepGProp::SurfaceProperties(f, sp);
		gp_Pnt cm = sp.CentreOfMass();
		// the centre of mass snapped onto the surface; the normal there points out of the solid
		Handle(Geom_Surface) surf = BRep_Tool::Surface(f);
		GeomAPI_ProjectPointOnSurf proj(cm, surf);
		double u = 0, v = 0;
		gp_Pnt pt = cm;
		if (proj.NbPoints() > 0) {
			proj.LowerDistanceParameters(u, v);
			pt = proj.NearestPoint();
		}
		BRepGProp_Face gf(f);
		gp_Pnt p2;
		gp_Vec nv;
		gf.Normal(u, v, p2, nv);
		if (nv.Magnitude() > 1e-12) {
			nv.Normalize();
		}
		BRepAdaptor_Surface bs(f);
		const char *type = "other";
		switch (bs.GetType()) {
			case GeomAbs_Plane: type = "plane"; break;
			case GeomAbs_Cylinder: type = "cylinder"; break;
			case GeomAbs_Cone: type = "cone"; break;
			case GeomAbs_Sphere: type = "sphere"; break;
			case GeomAbs_Torus: type = "torus"; break;
			default: break;
		}
		Dictionary d;
		d["id"] = i;
		d["center"] = v3(pt);
		d["mass_center"] = v3(cm);
		d["normal"] = Vector3(nv.X(), nv.Y(), nv.Z());
		d["area"] = sp.Mass();
		d["type"] = String(type);
		out.push_back(d);
	}
	return out;
	KCAD_CATCH("faces", Array())
}

int KineCAD::fillet_edges(int id, const PackedInt32Array &ids, double radius) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (ids.is_empty()) {
		g_err = "fillet_edges: no edges given";
		return 0;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape em;
	TopExp::MapShapes(s, TopAbs_EDGE, em);
	BRepFilletAPI_MakeFillet mk(s);
	for (int i = 0; i < ids.size(); i++) {
		if (ids[i] < 1 || ids[i] > em.Extent()) {
			g_err = "fillet_edges: no such edge id";
			return 0;
		}
		mk.Add(radius, TopoDS::Edge(em(ids[i])));
	}
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "fillet failed (radius too large for an edge?)";
		return 0;
	}
	return kc_put(mk.Shape());
	KCAD_CATCH("fillet_edges", 0)
}

int KineCAD::chamfer_edges(int id, const PackedInt32Array &ids, double dist) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (ids.is_empty()) {
		g_err = "chamfer_edges: no edges given";
		return 0;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape em;
	TopExp::MapShapes(s, TopAbs_EDGE, em);
	BRepFilletAPI_MakeChamfer mk(s);
	for (int i = 0; i < ids.size(); i++) {
		if (ids[i] < 1 || ids[i] > em.Extent()) {
			g_err = "chamfer_edges: no such edge id";
			return 0;
		}
		mk.Add(dist, TopoDS::Edge(em(ids[i])));
	}
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "chamfer failed (distance too large for an edge?)";
		return 0;
	}
	return kc_put(mk.Shape());
	KCAD_CATCH("chamfer_edges", 0)
}

// outward unit normal of a face at its centre of mass (same rule as faces())
static bool kc_face_outward(const TopoDS_Face &f, gp_Dir &out) {
	GProp_GProps sp;
	BRepGProp::SurfaceProperties(f, sp);
	gp_Pnt cm = sp.CentreOfMass();
	Handle(Geom_Surface) surf = BRep_Tool::Surface(f);
	GeomAPI_ProjectPointOnSurf proj(cm, surf);
	double u = 0, v = 0;
	if (proj.NbPoints() > 0) {
		proj.LowerDistanceParameters(u, v);
	}
	BRepGProp_Face gf(f);
	gp_Pnt p2;
	gp_Vec nv;
	gf.Normal(u, v, p2, nv);
	if (nv.Magnitude() < 1e-12) {
		return false;
	}
	out = gp_Dir(nv);
	return true;
}

int KineCAD::offset_face(int id, int face_id, double dist) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (dist == 0.0) {
		g_err = "offset_face: distance is zero";
		return 0;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape fm;
	TopExp::MapShapes(s, TopAbs_FACE, fm);
	if (face_id < 1 || face_id > fm.Extent()) {
		g_err = "offset_face: no such face id";
		return 0;
	}
	TopoDS_Face f = TopoDS::Face(fm(face_id));
	gp_Dir n;
	if (!kc_face_outward(f, n)) {
		g_err = "offset_face: the face has no normal";
		return 0;
	}
	// the slab from the face along its outward normal (dist > 0: outside, fused) or along the inward normal (dist < 0: cut out)
	BRepPrimAPI_MakePrism slab(f, gp_Vec(n) * dist);
	slab.Build();
	if (!slab.IsDone()) {
		g_err = "offset_face: the prism failed";
		return 0;
	}
	TopoDS_Shape tool = slab.Shape();
	if (dist > 0) {
		BRepAlgoAPI_Fuse op(s, tool);
		if (!op.IsDone() || op.HasErrors()) {
			g_err = "offset_face: fuse failed";
			return 0;
		}
		ShapeUpgrade_UnifySameDomain unify(op.Shape(), true, true, true);
		unify.Build();
		return kc_put(unify.Shape());
	}
	BRepAlgoAPI_Cut op(s, tool);
	if (!op.IsDone() || op.HasErrors()) {
		g_err = "offset_face: cut failed";
		return 0;
	}
	ShapeUpgrade_UnifySameDomain unify(op.Shape(), true, true, true);
	unify.Build();
	return kc_put(unify.Shape());
	KCAD_CATCH("offset_face", 0)
}

int KineCAD::draft_faces(int id, const PackedInt32Array &face_ids, double angle, const Vector3 &pull_dir, const Vector3 &neutral_origin) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (face_ids.is_empty()) {
		g_err = "draft_faces: no faces given";
		return 0;
	}
	if (pull_dir.length_squared() < 1e-12) {
		g_err = "draft_faces: pull direction is zero";
		return 0;
	}
	KCAD_TRY
	TopTools_IndexedMapOfShape fm;
	TopExp::MapShapes(s, TopAbs_FACE, fm);
	gp_Dir pd(pull_dir.x, pull_dir.y, pull_dir.z);
	gp_Pln neutral(gp_Pnt(neutral_origin.x, neutral_origin.y, neutral_origin.z), pd);
	BRepOffsetAPI_DraftAngle mk(s);
	for (int i = 0; i < face_ids.size(); i++) {
		if (face_ids[i] < 1 || face_ids[i] > fm.Extent()) {
			g_err = "draft_faces: no such face id";
			return 0;
		}
		mk.Add(TopoDS::Face(fm(face_ids[i])), pd, angle, neutral);
		if (!mk.AddDone()) {
			g_err = "draft_faces: this face cannot take a draft";
			return 0;
		}
	}
	mk.Build();
	if (!mk.IsDone()) {
		g_err = "draft failed (angle too big, or the faces do not meet the neutral plane?)";
		return 0;
	}
	return kc_put(mk.Shape());
	KCAD_CATCH("draft_faces", 0)
}

int KineCAD::mirror(int id, const Vector3 &origin, const Vector3 &normal) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (normal.length_squared() < 1e-18) {
		g_err = "mirror: zero plane normal";
		return 0;
	}
	KCAD_TRY
	gp_Trsf t;
	t.SetMirror(gp_Ax2(gp_Pnt(origin.x, origin.y, origin.z), gp_Dir(normal.x, normal.y, normal.z)));
	BRepBuilderAPI_Transform tr(s, t, true);
	return kc_put_solid(tr.Shape());
	KCAD_CATCH("mirror", 0)
}

int KineCAD::pattern_linear(int id, const Vector3 &step, int count) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (count < 1) {
		g_err = "pattern: count must be >= 1";
		return 0;
	}
	KCAD_TRY
	TopoDS_Shape acc = s;
	for (int i = 1; i < count; i++) {
		gp_Trsf t;
		t.SetTranslation(gp_Vec(step.x * i, step.y * i, step.z * i));
		acc = fuse_all(acc, BRepBuilderAPI_Transform(s, t, true).Shape());
		if (acc.IsNull()) {
			g_err = "pattern: fuse failed";
			return 0;
		}
	}
	return kc_put(acc);
	KCAD_CATCH("pattern_linear", 0)
}

int KineCAD::pattern_circular(int id, const Vector3 &ao, const Vector3 &ad, int count, double total) {
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return 0;
	}
	if (count < 1 || ad.length_squared() < 1e-18) {
		g_err = "pattern: count must be >= 1 and the axis non-zero";
		return 0;
	}
	KCAD_TRY
	gp_Ax1 ax(gp_Pnt(ao.x, ao.y, ao.z), gp_Dir(ad.x, ad.y, ad.z));
	// a full turn spreads the copies evenly round it; a partial angle is the span from the first copy to the last
	const bool full = std::fabs(total) >= 2.0 * M_PI - 1e-9;
	const double step = count < 2 ? 0.0 : (full ? total / count : total / (count - 1));
	TopoDS_Shape acc = s;
	for (int i = 1; i < count; i++) {
		gp_Trsf t;
		t.SetRotation(ax, step * i);
		acc = fuse_all(acc, BRepBuilderAPI_Transform(s, t, true).Shape());
		if (acc.IsNull()) {
			g_err = "pattern: fuse failed";
			return 0;
		}
	}
	return kc_put(acc);
	KCAD_CATCH("pattern_circular", 0)
}

Dictionary KineCAD::mass_properties(int id) {
	Dictionary d;
	TopoDS_Shape s;
	if (!kc_get(id, s)) {
		return d;
	}
	KCAD_TRY
	GProp_GProps vp, sp;
	BRepGProp::VolumePropertiesGK(s, vp, 1e-9, false, true, true, true); // + centre of mass and inertia
	BRepGProp::SurfaceProperties(s, sp, 1e-9);
	gp_Mat m = vp.MatrixOfInertia();
	d["volume"] = vp.Mass();
	d["area"] = sp.Mass();
	d["center"] = v3(vp.CentreOfMass());
	d["inertia"] = Basis(Vector3(m(1, 1), m(2, 1), m(3, 1)), Vector3(m(1, 2), m(2, 2), m(3, 2)), Vector3(m(1, 3), m(2, 3), m(3, 3)));
	return d;
	KCAD_CATCH("mass_properties", Dictionary())
}

void KineCAD::release(int id) {
	std::lock_guard<std::mutex> lk(g_mu);
	g_shapes.erase(id);
}
void KineCAD::release_all() {
	std::lock_guard<std::mutex> lk(g_mu);
	g_shapes.clear();
}
int KineCAD::live_count() {
	std::lock_guard<std::mutex> lk(g_mu);
	return (int)g_shapes.size();
}



// s249n DIRECT SHELL: a mesh whose triangles already share vertex INDICES (every edge used by exactly two triangles, once each way) needs no sewing:
// one vertex per index, one edge per undirected pair, one planar face per triangle. Sewing searches for the matches the indices already name (the
// 54k-triangle temple roofs took 33 s that way). Anything else (unwelded copies, open or non-manifold edges, a bad index) returns false and the
// caller sews as before, so the solid is the same one and only the time differs.
static bool kc_direct_solid(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, TopoDS_Solid &r_solid) {
	const int nv = p_verts.size();
	std::unordered_map<long long, int> use; // undirected edge -> bit 1: seen a->b (a<b), bit 2: seen b->a
	std::vector<char> ok_tri(p_tris.size() / 3, 0);
	for (int t = 0; t + 2 < p_tris.size(); t += 3) {
		int ix[3] = { p_tris[t], p_tris[t + 1], p_tris[t + 2] };
		for (int k = 0; k < 3; k++) {
			if (ix[k] < 0 || ix[k] >= nv) {
				return false;
			}
		}
		if (ix[0] == ix[1] || ix[1] == ix[2] || ix[0] == ix[2]) {
			continue;
		}
		ok_tri[t / 3] = 1;
		for (int k = 0; k < 3; k++) {
			int a = ix[k], b = ix[(k + 1) % 3];
			long long key = (long long)std::min(a, b) * (long long)nv + std::max(a, b);
			int bit = a < b ? 1 : 2;
			int &u = use[key];
			if (u & bit) {
				return false; // the same direction twice: non-manifold or flipped
			}
			u |= bit;
		}
	}
	for (auto &kv : use) {
		if (kv.second != 3) {
			return false; // open edge
		}
	}
	std::vector<TopoDS_Vertex> vtx(nv);
	std::vector<char> have(nv, 0);
	std::unordered_map<long long, TopoDS_Edge> edges;
	BRep_Builder bb;
	TopoDS_Shell shell;
	bb.MakeShell(shell);
	int nf = 0;
	for (int t = 0; t + 2 < p_tris.size(); t += 3) {
		if (!ok_tri[t / 3]) {
			continue;
		}
		int ix[3] = { p_tris[t], p_tris[t + 1], p_tris[t + 2] };
		for (int k = 0; k < 3; k++) {
			if (!have[ix[k]]) {
				Vector3 v = p_verts[ix[k]];
				vtx[ix[k]] = BRepBuilderAPI_MakeVertex(gp_Pnt(v.x, v.y, v.z));
				have[ix[k]] = 1;
			}
		}
		BRepBuilderAPI_MakeWire mw;
		for (int k = 0; k < 3; k++) {
			int a = ix[k], b = ix[(k + 1) % 3];
			int lo = std::min(a, b), hi = std::max(a, b);
			long long key = (long long)lo * (long long)nv + hi;
			auto it = edges.find(key);
			if (it == edges.end()) {
				BRepBuilderAPI_MakeEdge me(vtx[lo], vtx[hi]);
				if (!me.IsDone()) {
					return false;
				}
				it = edges.emplace(key, me.Edge()).first;
			}
			TopoDS_Edge e = it->second;
			mw.Add(a < b ? e : TopoDS::Edge(e.Reversed()));
			if (!mw.IsDone()) {
				return false;
			}
		}
		Vector3 va = p_verts[ix[0]], vb = p_verts[ix[1]], vc = p_verts[ix[2]];
		gp_Vec n = gp_Vec(gp_Pnt(va.x, va.y, va.z), gp_Pnt(vb.x, vb.y, vb.z)).Crossed(gp_Vec(gp_Pnt(va.x, va.y, va.z), gp_Pnt(vc.x, vc.y, vc.z)));
		if (n.Magnitude() < 1e-30) {
			return false;
		}
		BRepBuilderAPI_MakeFace mf(gp_Pln(gp_Pnt(va.x, va.y, va.z), gp_Dir(n)), mw.Wire(), true); // the plane is known: no plane search
		if (!mf.IsDone()) {
			return false;
		}
		bb.Add(shell, mf.Face());
		nf++;
	}
	if (nf < 4) {
		return false;
	}
	shell.Closed(true);
	BRepBuilderAPI_MakeSolid ms(shell);
	if (!ms.IsDone()) {
		return false;
	}
	r_solid = ms.Solid();
	BRepLib::OrientClosedSolid(r_solid);
	return true;
}

// s155 MESH -> SOLID: every triangle becomes a planar face, the faces are sewn into one shell (shared vertices, tolerance p_tol metres),
// the shell must be CLOSED and be the only one, then it becomes a solid with its faces pointing outward. 0 + last_error() otherwise.
int KineCAD::solid_from_mesh(const PackedVector3Array &p_verts, const PackedInt32Array &p_tris, double p_tol) {
	if (p_tris.size() < 12 || p_tris.size() % 3 != 0) {
		g_err = "mesh: needs at least 4 triangles";
		return 0;
	}
	KCAD_TRY
	if (std::getenv("KINE_NO_DIRECT") == nullptr) {
		TopoDS_Solid direct;
		if (kc_direct_solid(p_verts, p_tris, direct)) {
			return kc_put_solid(direct);
		}
	}
	BRepBuilderAPI_Sewing sew(p_tol > 0.0 ? p_tol : 1e-6, true, true, true, false);
	int added = 0;
	for (int t = 0; t + 2 < p_tris.size(); t += 3) {
		int ia = p_tris[t], ib = p_tris[t + 1], ic = p_tris[t + 2];
		if (ia < 0 || ib < 0 || ic < 0 || ia >= p_verts.size() || ib >= p_verts.size() || ic >= p_verts.size()) {
			g_err = "mesh: a triangle names a corner that is not there";
			return 0;
		}
		if (ia == ib || ib == ic || ia == ic) {
			continue;
		}
		Vector3 a = p_verts[ia], b = p_verts[ib], c = p_verts[ic];
		BRepBuilderAPI_MakePolygon poly(gp_Pnt(a.x, a.y, a.z), gp_Pnt(b.x, b.y, b.z), gp_Pnt(c.x, c.y, c.z), true);
		if (!poly.IsDone()) {
			continue; // a zero-area sliver: the sewing closes over it or the shell stays open (checked below)
		}
		BRepBuilderAPI_MakeFace mf(poly.Wire(), true);
		if (!mf.IsDone()) {
			continue;
		}
		sew.Add(mf.Face());
		added++;
	}
	if (added < 4) {
		g_err = "mesh: no usable triangles";
		return 0;
	}
	sew.Perform();
	TopoDS_Shape sewn = sew.SewedShape();
	if (sewn.IsNull()) {
		g_err = "mesh: the triangles could not be joined";
		return 0;
	}
	if (sew.NbFreeEdges() > 0 || sew.NbMultipleEdges() > 0 || sew.NbDegeneratedShapes() > 0) {
		g_err = std::string("mesh: not closed (") + std::to_string(sew.NbFreeEdges()) + " open edges, " + std::to_string(sew.NbMultipleEdges()) + " shared by 3+ faces)";
		return 0;
	}
	TopoDS_Shell shell;
	int shells = 0;
	for (TopExp_Explorer ex(sewn, TopAbs_SHELL); ex.More(); ex.Next()) {
		shell = TopoDS::Shell(ex.Current());
		shells++;
	}
	if (shells != 1) {
		g_err = "mesh: it is " + std::to_string(shells) + " separate shells, a solid part needs exactly one";
		return 0;
	}
	BRepBuilderAPI_MakeSolid ms(shell);
	if (!ms.IsDone()) {
		g_err = "mesh: the shell could not become a solid";
		return 0;
	}
	TopoDS_Solid sol = ms.Solid();
	BRepLib::OrientClosedSolid(sol);
	return kc_put_solid(sol);
	KCAD_CATCH("solid_from_mesh", 0)
}


// s155b SOLID OFFSET (KineCAD version 5): every face of the solid moves along its outward normal by p_dist metres (> 0 thicker, < 0 thinner:
// holes shrink when it grows). First the sharp-corner join (GeomAbs_Intersection: a box +1 mm is exactly 2 mm wider on each axis, edges stay sharp),
// and when the kernel refuses that or returns something invalid, the rounded join (GeomAbs_Arc). 0 + last_error() when both fail
// (a wall thinner than 2 x |d|, a feature that would vanish).
int KineCAD::offset(int p_id, double p_dist) {
	TopoDS_Shape s;
	if (!kc_get(p_id, s)) {
		return 0;
	}
	KCAD_TRY
	if (std::fabs(p_dist) < 1e-9) {
		return kc_put(s);
	}
	double vol0 = 0.0;
	{
		GProp_GProps gp;
		BRepGProp::VolumeProperties(s, gp);
		vol0 = gp.Mass();
	}
	std::string why;
	const GeomAbs_JoinType joins[2] = { GeomAbs_Intersection, GeomAbs_Arc };
	for (int j = 0; j < 2; j++) {
		try {
			BRepOffsetAPI_MakeOffsetShape mk;
			mk.PerformByJoin(s, p_dist, 1e-6, BRepOffset_Skin, j == 0, false, joins[j]);
			if (!mk.IsDone()) {
				why += " [join " + std::to_string(j) + ": not done]";
				continue;
			}
			TopoDS_Shape r = mk.Shape();
			if (r.IsNull()) {
				why += " [join " + std::to_string(j) + ": null]";
				continue;
			}
			// take the one solid (the result may be wrapped in a compound)
			TopoDS_Shape sol;
			int n = 0;
			for (TopExp_Explorer ex(r, TopAbs_SOLID); ex.More(); ex.Next()) {
				sol = ex.Current();
				n++;
			}
			if (n == 0) {   // the kernel sometimes hands back the closed shell without wrapping it in a solid
				int shn = 0;
				TopoDS_Shell shl;
				for (TopExp_Explorer ex(r, TopAbs_SHELL); ex.More(); ex.Next()) {
					shl = TopoDS::Shell(ex.Current());
					shn++;
				}
				if (shn == 1) {
					BRepBuilderAPI_MakeSolid ms(shl);
					if (ms.IsDone()) {
						TopoDS_Solid so = ms.Solid();
						BRepLib::OrientClosedSolid(so);
						sol = so;
						n = 1;
					}
				}
			}
			if (n != 1) {
				why += " [join " + std::to_string(j) + ": " + std::to_string(n) + " solids]";
				continue;
			}
			BRepCheck_Analyzer an(sol);
			if (!an.IsValid()) {
				why += " [join " + std::to_string(j) + ": invalid]";
				continue;
			}
			GProp_GProps gp;
			BRepGProp::VolumeProperties(sol, gp);
			double v = gp.Mass();
			if (v <= 1e-15 || (p_dist > 0.0 && v <= vol0) || (p_dist < 0.0 && v >= vol0)) {
				why += " [join " + std::to_string(j) + ": volume " + std::to_string(v) + " vs " + std::to_string(vol0) + "]";
				continue;
			}
			return kc_put(sol);
		} catch (Standard_Failure &e) {
			why += std::string(" [join ") + std::to_string(j) + ": threw " + e.what() + "]";
			continue;
		}
	}
	g_err = "offset: the kernel could not move every face by that distance" + why;
	return 0;
	KCAD_CATCH("offset", 0)
}
