#include "StepBridge.h"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBndLib.hxx>
#include <BRepGProp.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <GProp_GProps.hxx>
#include <Poly_PolygonOnTriangulation.hxx>
#include <Poly_Triangulation.hxx>
#include <Quantity_Color.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <Standard_Failure.hxx>
#include <TDF_LabelSequence.hxx>
#include <TDataStd_Name.hxx>
#include <TDocStd_Document.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_ColorTool.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>

#include <algorithm>
#include <cmath>
#include <set>
#include <string>
#include <vector>

namespace {

// Mesh fineness: chord deviation relative to the part's bounding box diagonal, and max angle between segments
constexpr double relativeLinearDeflection = 0.002;
constexpr double angularDeflection = 0.25;
// Relative accuracy for the exact volume integration
constexpr double volumeIntegrationTolerance = 1.0e-6;
constexpr char pathSeparator = '\x1f';

struct PartStorage {
    std::string name;
    std::string definitionName;
    std::string path;
    bool hasColor = false;
    float color[3] = {0, 0, 0};
    double volume = 0;
    LibraStepVector centroid = {0, 0, 0};
    double inertia[9] = {0};
    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<uint32_t> indices;
    std::vector<LibraStepFace> faces;
    std::vector<int32_t> faceEdges;
    std::vector<LibraStepEdge> edges;
    std::vector<float> edgePoints;
    std::vector<float> vertices;
};

struct Storage {
    std::string errorMessage;
    std::vector<PartStorage> parts;
    std::vector<LibraStepPart> cParts;
};

struct Context {
    Handle(XCAFDoc_ShapeTool) shapeTool;
    Handle(XCAFDoc_ColorTool) colorTool;
    double metersPerUnit = 0.001;
    Storage *storage = nullptr;
};

struct InheritedColor {
    bool isSet = false;
    Quantity_Color color;
};

std::string labelName(const TDF_Label &label) {
    Handle(TDataStd_Name) name;
    if (!label.FindAttribute(TDataStd_Name::GetID(), name)) {
        return "";
    }
    const TCollection_ExtendedString &text = name->Get();
    std::vector<char> buffer(static_cast<size_t>(text.LengthOfCString()) + 1, '\0');
    Standard_PCharacter cursor = buffer.data();
    text.ToUTF8CString(cursor);
    return std::string(buffer.data());
}

bool labelColor(const Context &context, const TDF_Label &label, Quantity_Color &color) {
    return context.colorTool->GetColor(label, XCAFDoc_ColorSurf, color)
        || context.colorTool->GetColor(label, XCAFDoc_ColorGen, color);
}

// A part's color: on its own label, or failing that on one of its sub-shapes (Fusion styles solids)
bool partColor(const Context &context, const TDF_Label &label, Quantity_Color &color) {
    if (labelColor(context, label, color)) {
        return true;
    }
    TDF_LabelSequence subShapes;
    XCAFDoc_ShapeTool::GetSubShapes(label, subShapes);
    for (Standard_Integer index = 1; index <= subShapes.Length(); ++index) {
        if (labelColor(context, subShapes.Value(index), color)) {
            return true;
        }
    }
    return false;
}

LibraStepVector vector(const gp_XYZ &value, double scale) {
    return {value.X() * scale, value.Y() * scale, value.Z() * scale};
}

void append(std::vector<float> &values, const gp_XYZ &point, double scale) {
    values.push_back(static_cast<float>(point.X() * scale));
    values.push_back(static_cast<float>(point.Y() * scale));
    values.push_back(static_cast<float>(point.Z() * scale));
}

void addVolumeProperties(PartStorage &part, const TopoDS_Shape &shape, double scale) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties, volumeIntegrationTolerance);
    double volume = properties.Mass();
    gp_Mat inertia = properties.MatrixOfInertia();
    // A solid with reversed orientation integrates to a negative volume
    double sign = volume < 0 ? -1.0 : 1.0;
    part.volume = sign * volume * scale * scale * scale;
    part.centroid = vector(properties.CentreOfMass().XYZ(), scale);
    double inertiaScale = sign * std::pow(scale, 5);
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            part.inertia[row * 3 + column] = inertia.Value(row + 1, column + 1) * inertiaScale;
        }
    }
}

void addFace(PartStorage &part, const TopoDS_Face &face, const TopTools_IndexedMapOfShape &edgeMap, double scale) {
    LibraStepFace record = {};
    record.triangleStart = static_cast<int32_t>(part.indices.size() / 3);
    bool reversed = face.Orientation() == TopAbs_REVERSED;

    TopLoc_Location location;
    Handle(Poly_Triangulation) triangulation = BRep_Tool::Triangulation(face, location);
    if (!triangulation.IsNull()) {
        if (!triangulation->HasNormals()) {
            BRepLib_ToolTriangulatedShape::ComputeNormals(face, triangulation);
        }
        gp_Trsf transform = location.Transformation();
        uint32_t base = static_cast<uint32_t>(part.positions.size() / 3);
        for (Standard_Integer node = 1; node <= triangulation->NbNodes(); ++node) {
            append(part.positions, triangulation->Node(node).Transformed(transform).XYZ(), scale);
            gp_Dir normal = triangulation->Normal(node).Transformed(transform);
            if (reversed) {
                normal.Reverse();
            }
            append(part.normals, normal.XYZ(), 1.0);
        }
        for (Standard_Integer triangle = 1; triangle <= triangulation->NbTriangles(); ++triangle) {
            Standard_Integer first, second, third;
            triangulation->Triangle(triangle).Get(first, second, third);
            if (reversed) {
                std::swap(second, third);
            }
            part.indices.push_back(base + static_cast<uint32_t>(first - 1));
            part.indices.push_back(base + static_cast<uint32_t>(second - 1));
            part.indices.push_back(base + static_cast<uint32_t>(third - 1));
        }
    }
    record.triangleCount = static_cast<int32_t>(part.indices.size() / 3) - record.triangleStart;

    GProp_GProps surfaceProperties;
    BRepGProp::SurfaceProperties(face, surfaceProperties);
    gp_Pnt areaCentroid = surfaceProperties.CentreOfMass();

    BRepAdaptor_Surface surface(face);
    gp_Ax1 axis;
    bool hasAxis = false;
    switch (surface.GetType()) {
    case GeomAbs_Plane: {
        record.kind = LibraStepFacePlane;
        gp_Dir normal = surface.Plane().Axis().Direction();
        if (reversed) {
            normal.Reverse();
        }
        record.center = vector(areaCentroid.XYZ(), scale);
        record.direction = vector(normal.XYZ(), 1.0);
        break;
    }
    case GeomAbs_Cylinder:
        record.kind = LibraStepFaceCylinder;
        axis = surface.Cylinder().Axis();
        record.radius = surface.Cylinder().Radius() * scale;
        hasAxis = true;
        break;
    case GeomAbs_Cone:
        record.kind = LibraStepFaceCone;
        axis = surface.Cone().Axis();
        record.radius = surface.Cone().RefRadius() * scale;
        hasAxis = true;
        break;
    case GeomAbs_Torus:
        record.kind = LibraStepFaceTorus;
        axis = surface.Torus().Axis();
        record.radius = surface.Torus().MajorRadius() * scale;
        hasAxis = true;
        break;
    case GeomAbs_Sphere:
        record.kind = LibraStepFaceSphere;
        record.center = vector(surface.Sphere().Location().XYZ(), scale);
        record.radius = surface.Sphere().Radius() * scale;
        break;
    default:
        record.kind = LibraStepFaceOther;
        record.center = vector(areaCentroid.XYZ(), scale);
        break;
    }
    if (hasAxis) {
        // The point on the axis level with the middle of the face, rather than the axis' arbitrary origin
        gp_XYZ origin = axis.Location().XYZ();
        gp_XYZ direction = axis.Direction().XYZ();
        gp_XYZ onAxis = origin + direction * (areaCentroid.XYZ() - origin).Dot(direction);
        record.center = vector(onAxis, scale);
        record.direction = vector(direction, 1.0);
    }

    record.edgeStart = static_cast<int32_t>(part.faceEdges.size());
    std::set<int32_t> seen;
    for (TopExp_Explorer explorer(face, TopAbs_EDGE); explorer.More(); explorer.Next()) {
        int32_t index = static_cast<int32_t>(edgeMap.FindIndex(explorer.Current())) - 1;
        if (index >= 0 && seen.insert(index).second) {
            part.faceEdges.push_back(index);
        }
    }
    record.edgeCount = static_cast<int32_t>(part.faceEdges.size()) - record.edgeStart;
    part.faces.push_back(record);
}

// Seam edges (where a cylinder's surface wraps onto itself) aren't real edges, so they get no polyline
bool isSeam(const TopoDS_Edge &edge, const TopTools_ListOfShape &faces) {
    for (const TopoDS_Shape &face : faces) {
        if (BRep_Tool::IsClosed(edge, TopoDS::Face(face))) {
            return true;
        }
    }
    return false;
}

// The edge's points from an adjacent face's mesh, so the line sits exactly on the rendered faces
bool appendMeshPolyline(PartStorage &part, const TopoDS_Edge &edge, const TopTools_ListOfShape &faces, double scale) {
    for (const TopoDS_Shape &face : faces) {
        TopLoc_Location location;
        Handle(Poly_Triangulation) triangulation = BRep_Tool::Triangulation(TopoDS::Face(face), location);
        if (triangulation.IsNull()) {
            continue;
        }
        Handle(Poly_PolygonOnTriangulation) polygon = BRep_Tool::PolygonOnTriangulation(edge, triangulation, location);
        if (polygon.IsNull()) {
            continue;
        }
        gp_Trsf transform = location.Transformation();
        for (Standard_Integer index = 1; index <= polygon->NbNodes(); ++index) {
            append(part.edgePoints, triangulation->Node(polygon->Node(index)).Transformed(transform).XYZ(), scale);
        }
        return true;
    }
    return false;
}

void addEdge(PartStorage &part, const TopoDS_Edge &edge, const TopTools_ListOfShape &faces, double curvatureDeflection, double scale) {
    LibraStepEdge record = {};
    record.pointStart = static_cast<int32_t>(part.edgePoints.size() / 3);
    if (!BRep_Tool::Degenerated(edge) && !isSeam(edge, faces)) {
        BRepAdaptor_Curve curve(edge);
        switch (curve.GetType()) {
        case GeomAbs_Line:
            record.kind = LibraStepEdgeLine;
            record.direction = vector(curve.Line().Direction().XYZ(), 1.0);
            break;
        case GeomAbs_Circle:
            record.kind = LibraStepEdgeCircle;
            record.center = vector(curve.Circle().Location().XYZ(), scale);
            record.direction = vector(curve.Circle().Axis().Direction().XYZ(), 1.0);
            record.radius = curve.Circle().Radius() * scale;
            break;
        default:
            record.kind = LibraStepEdgeOther;
            break;
        }
        if (!appendMeshPolyline(part, edge, faces, scale)) {
            GCPnts_TangentialDeflection sampler(curve, angularDeflection, curvatureDeflection);
            for (Standard_Integer index = 1; index <= sampler.NbPoints(); ++index) {
                append(part.edgePoints, sampler.Value(index).XYZ(), scale);
            }
        }
    }
    record.pointCount = static_cast<int32_t>(part.edgePoints.size() / 3) - record.pointStart;
    part.edges.push_back(record);
}

void addPart(Context &context, const TDF_Label &label, const TopoDS_Shape &shape, const std::string &name,
             const std::vector<std::string> &path, const InheritedColor &inherited) {
    PartStorage part;
    part.name = name;
    part.definitionName = labelName(label);
    for (size_t index = 0; index < path.size(); ++index) {
        if (index > 0) {
            part.path.push_back(pathSeparator);
        }
        part.path += path[index];
    }

    Quantity_Color color;
    bool hasColor = partColor(context, label, color);
    if (!hasColor && inherited.isSet) {
        color = inherited.color;
        hasColor = true;
    }
    if (hasColor) {
        double red, green, blue;
        color.Values(red, green, blue, Quantity_TOC_sRGB);
        part.hasColor = true;
        part.color[0] = static_cast<float>(red);
        part.color[1] = static_cast<float>(green);
        part.color[2] = static_cast<float>(blue);
    }

    double scale = context.metersPerUnit;
    addVolumeProperties(part, shape, scale);

    Bnd_Box bounds;
    BRepBndLib::Add(shape, bounds);
    double diagonal = bounds.IsVoid() ? 1.0 : std::sqrt(bounds.SquareExtent());
    double linearDeflection = std::max(diagonal * relativeLinearDeflection, 1.0e-3);
    BRepMesh_IncrementalMesh mesher(shape, linearDeflection, Standard_False, angularDeflection, Standard_True);

    TopTools_IndexedMapOfShape faceMap, edgeMap, vertexMap;
    TopExp::MapShapes(shape, TopAbs_FACE, faceMap);
    TopExp::MapShapes(shape, TopAbs_EDGE, edgeMap);
    TopExp::MapShapes(shape, TopAbs_VERTEX, vertexMap);
    TopTools_IndexedDataMapOfShapeListOfShape edgeFaces;
    TopExp::MapShapesAndAncestors(shape, TopAbs_EDGE, TopAbs_FACE, edgeFaces);

    for (Standard_Integer index = 1; index <= faceMap.Extent(); ++index) {
        addFace(part, TopoDS::Face(faceMap(index)), edgeMap, scale);
    }
    for (Standard_Integer index = 1; index <= edgeMap.Extent(); ++index) {
        const TopoDS_Edge &edge = TopoDS::Edge(edgeMap(index));
        const TopTools_ListOfShape *faces = edgeFaces.Seek(edge);
        addEdge(part, edge, faces ? *faces : TopTools_ListOfShape(), linearDeflection, scale);
    }
    for (Standard_Integer index = 1; index <= vertexMap.Extent(); ++index) {
        append(part.vertices, BRep_Tool::Pnt(TopoDS::Vertex(vertexMap(index))).XYZ(), scale);
    }

    context.storage->parts.push_back(std::move(part));
}

void walk(Context &context, const TDF_Label &label, const TopLoc_Location &location, const std::string &name,
          std::vector<std::string> &path, InheritedColor inherited) {
    Quantity_Color color;
    if (labelColor(context, label, color)) {
        inherited = {true, color};
    }
    if (!XCAFDoc_ShapeTool::IsAssembly(label)) {
        TopoDS_Shape shape = XCAFDoc_ShapeTool::GetShape(label);
        if (!shape.IsNull()) {
            addPart(context, label, shape.Moved(location), name, path, inherited);
        }
        return;
    }
    path.push_back(name);
    TDF_LabelSequence components;
    XCAFDoc_ShapeTool::GetComponents(label, components, Standard_False);
    for (Standard_Integer index = 1; index <= components.Length(); ++index) {
        TDF_Label component = components.Value(index);
        TDF_Label referred;
        if (!XCAFDoc_ShapeTool::GetReferredShape(component, referred)) {
            continue;
        }
        std::string componentName = labelName(component);
        if (componentName.empty()) {
            componentName = labelName(referred);
        }
        InheritedColor componentColor = inherited;
        if (labelColor(context, component, color)) {
            componentColor = {true, color};
        }
        walk(context, referred, location * XCAFDoc_ShapeTool::GetLocation(component), componentName, path, componentColor);
    }
    path.pop_back();
}

void importFile(const char *path, Storage &storage) {
    Handle(TDocStd_Document) document;
    XCAFApp_Application::GetApplication()->NewDocument("MDTV-XCAF", document);
    // Read into millimeters (OCCT's tolerances are tuned for mm), then convert to meters on output
    XCAFDoc_DocumentTool::SetLengthUnit(document, 0.001);

    STEPCAFControl_Reader reader;
    reader.SetNameMode(Standard_True);
    reader.SetColorMode(Standard_True);
    if (reader.ReadFile(path) != IFSelect_RetDone) {
        storage.errorMessage = "Couldn't read the STEP file.";
        return;
    }
    if (!reader.Transfer(document)) {
        storage.errorMessage = "Couldn't convert the STEP file's contents.";
        return;
    }

    Context context;
    context.shapeTool = XCAFDoc_DocumentTool::ShapeTool(document->Main());
    context.colorTool = XCAFDoc_DocumentTool::ColorTool(document->Main());
    context.storage = &storage;
    double unitInMeters = 0;
    if (XCAFDoc_DocumentTool::GetLengthUnit(document, unitInMeters) && unitInMeters > 0) {
        context.metersPerUnit = unitInMeters;
    }

    TDF_LabelSequence roots;
    context.shapeTool->GetFreeShapes(roots);
    for (Standard_Integer index = 1; index <= roots.Length(); ++index) {
        std::vector<std::string> assemblyPath;
        TDF_Label root = roots.Value(index);
        walk(context, root, TopLoc_Location(), labelName(root), assemblyPath, InheritedColor());
    }
    if (storage.parts.empty()) {
        storage.errorMessage = "The STEP file has no parts.";
    }
    XCAFApp_Application::GetApplication()->Close(document);
}

void exposeParts(Storage &storage) {
    for (const PartStorage &part : storage.parts) {
        LibraStepPart cPart = {};
        cPart.name = part.name.c_str();
        cPart.definitionName = part.definitionName.c_str();
        cPart.path = part.path.c_str();
        cPart.hasColor = part.hasColor ? 1 : 0;
        std::copy(std::begin(part.color), std::end(part.color), cPart.color);
        cPart.volume = part.volume;
        cPart.centroid = part.centroid;
        std::copy(std::begin(part.inertia), std::end(part.inertia), cPart.inertia);
        cPart.positions = part.positions.data();
        cPart.normals = part.normals.data();
        cPart.vertexCount = static_cast<int32_t>(part.positions.size() / 3);
        cPart.indices = part.indices.data();
        cPart.triangleCount = static_cast<int32_t>(part.indices.size() / 3);
        cPart.faces = part.faces.data();
        cPart.faceCount = static_cast<int32_t>(part.faces.size());
        cPart.faceEdges = part.faceEdges.data();
        cPart.faceEdgeCount = static_cast<int32_t>(part.faceEdges.size());
        cPart.edges = part.edges.data();
        cPart.edgeCount = static_cast<int32_t>(part.edges.size());
        cPart.edgePoints = part.edgePoints.data();
        cPart.edgePointCount = static_cast<int32_t>(part.edgePoints.size() / 3);
        cPart.vertices = part.vertices.data();
        cPart.vertexPointCount = static_cast<int32_t>(part.vertices.size() / 3);
        storage.cParts.push_back(cPart);
    }
}

} // namespace

extern "C" LibraStepResult *libra_step_import(const char *path) {
    Storage *storage = new Storage();
    // OCCT reports failures as exceptions; none may cross into Swift
    try {
        importFile(path, *storage);
    } catch (const Standard_Failure &failure) {
        storage->errorMessage = std::string("OpenCASCADE error: ") + failure.GetMessageString();
    } catch (const std::exception &exception) {
        storage->errorMessage = std::string("Import error: ") + exception.what();
    } catch (...) {
        storage->errorMessage = "Unknown import error.";
    }

    LibraStepResult *result = new LibraStepResult();
    result->storage = storage;
    if (!storage->errorMessage.empty()) {
        storage->parts.clear();
        result->errorMessage = storage->errorMessage.c_str();
        return result;
    }
    exposeParts(*storage);
    result->parts = storage->cParts.data();
    result->partCount = static_cast<int32_t>(storage->cParts.size());
    return result;
}

extern "C" void libra_step_free(LibraStepResult *result) {
    if (result == nullptr) {
        return;
    }
    delete static_cast<Storage *>(result->storage);
    delete result;
}
