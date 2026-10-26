#include "kine_cad.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <BRepAdaptor_Surface.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepGProp.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepOffsetAPI_MakeThickSolid.hxx>
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
	ClassDB::bind_static_method("KineCAD", D_METHOD("release", "id"), &KineCAD::release);
	ClassDB::bind_static_method("KineCAD", D_METHOD("release_all"), &KineCAD::release_all);
	ClassDB::bind_static_method("KineCAD", D_METHOD("live_count"), &KineCAD::live_count);
}

int KineCAD::version() {
	return 1;
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
	BRepGProp::VolumeProperties(s, p);
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
	BRepGProp::SurfaceProperties(s, p);
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
	BRepMesh_IncrementalMesh inc(s, deflection, false, angle, false);
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
