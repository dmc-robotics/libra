// Writes STEP fixtures with known geometry for StepImportTests. Run from the repository root:
//
//   clang++ -std=c++17 -isystem /opt/homebrew/opt/opencascade/include/opencascade -Wno-deprecated-declarations \
//     Tools/generate_fixtures.cpp -o Tools/generate_fixtures -L/opt/homebrew/opt/opencascade/lib \
//     -lTKDESTEP -lTKDE -lTKXCAF -lTKCAF -lTKLCAF -lTKXSBase -lTKPrim -lTKTopAlgo -lTKBRep -lTKG3d -lTKMath -lTKernel \
//   && Tools/generate_fixtures LibraKit/Tests/StepImportTests/Fixtures
//
// assembly.step (millimeters), root assembly "Fixture":
//   "Box:1"       10 x 20 x 30 box, corner at the origin, red
//   "Box:2"       same box rotated 45° about Z, then moved to (100, 50, 0)
//   "Sub:1"       subassembly moved to (0, 0, 50), containing
//     "Cylinder:1"  radius 5, height 40 along Z, base centered on the subassembly origin
//
// duplicate_names.step, root assembly "Duplicates", where siblings share names:
//   "Part", "Part"  two box instances
//   "Group", "Group"  two instances of a subassembly holding one box, "Box"

#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <Quantity_Color.hxx>
#include <STEPCAFControl_Writer.hxx>
#include <TDataStd_Name.hxx>
#include <TDocStd_Document.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_ColorTool.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>
#include <gp_Trsf.hxx>

#include <cmath>
#include <iostream>
#include <string>

namespace {

void setName(const TDF_Label &label, const char *name) {
    TDataStd_Name::Set(label, TCollection_ExtendedString(name));
}

TopLoc_Location translation(double x, double y, double z) {
    gp_Trsf transform;
    transform.SetTranslation(gp_Vec(x, y, z));
    return TopLoc_Location(transform);
}

bool write(const Handle(TDocStd_Document) &document, const std::string &path) {
    STEPCAFControl_Writer writer;
    writer.SetNameMode(Standard_True);
    writer.SetColorMode(Standard_True);
    if (!writer.Transfer(document) || writer.Write(path.c_str()) != IFSelect_RetDone) {
        std::cerr << "couldn't write " << path << "\n";
        return false;
    }
    std::cout << "wrote " << path << "\n";
    return true;
}

bool writeAssembly(const std::string &path) {
    Handle(TDocStd_Document) document;
    XCAFApp_Application::GetApplication()->NewDocument("MDTV-XCAF", document);
    XCAFDoc_DocumentTool::SetLengthUnit(document, 0.001);
    Handle(XCAFDoc_ShapeTool) shapes = XCAFDoc_DocumentTool::ShapeTool(document->Main());
    Handle(XCAFDoc_ColorTool) colors = XCAFDoc_DocumentTool::ColorTool(document->Main());

    TDF_Label box = shapes->AddShape(BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape(), Standard_False);
    setName(box, "Box");
    colors->SetColor(box, Quantity_Color(1.0, 0.0, 0.0, Quantity_TOC_sRGB), XCAFDoc_ColorSurf);

    TDF_Label cylinder = shapes->AddShape(BRepPrimAPI_MakeCylinder(5.0, 40.0).Shape(), Standard_False);
    setName(cylinder, "Cylinder");

    TDF_Label subassembly = shapes->NewShape();
    setName(subassembly, "Sub");
    setName(shapes->AddComponent(subassembly, cylinder, TopLoc_Location()), "Cylinder:1");

    TDF_Label root = shapes->NewShape();
    setName(root, "Fixture");
    setName(shapes->AddComponent(root, box, TopLoc_Location()), "Box:1");
    gp_Trsf rotatedAndMoved;
    rotatedAndMoved.SetRotation(gp_Ax1(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)), M_PI / 4.0);
    rotatedAndMoved.SetTranslationPart(gp_Vec(100.0, 50.0, 0.0));
    setName(shapes->AddComponent(root, box, TopLoc_Location(rotatedAndMoved)), "Box:2");
    setName(shapes->AddComponent(root, subassembly, translation(0.0, 0.0, 50.0)), "Sub:1");
    shapes->UpdateAssemblies();
    return write(document, path);
}

bool writeDuplicateNames(const std::string &path) {
    Handle(TDocStd_Document) document;
    XCAFApp_Application::GetApplication()->NewDocument("MDTV-XCAF", document);
    XCAFDoc_DocumentTool::SetLengthUnit(document, 0.001);
    Handle(XCAFDoc_ShapeTool) shapes = XCAFDoc_DocumentTool::ShapeTool(document->Main());

    TDF_Label box = shapes->AddShape(BRepPrimAPI_MakeBox(10.0, 10.0, 10.0).Shape(), Standard_False);
    setName(box, "Box");
    TDF_Label group = shapes->NewShape();
    setName(group, "Group");
    setName(shapes->AddComponent(group, box, TopLoc_Location()), "Box");

    TDF_Label root = shapes->NewShape();
    setName(root, "Duplicates");
    setName(shapes->AddComponent(root, box, TopLoc_Location()), "Part");
    setName(shapes->AddComponent(root, box, translation(20.0, 0.0, 0.0)), "Part");
    setName(shapes->AddComponent(root, group, translation(0.0, 20.0, 0.0)), "Group");
    setName(shapes->AddComponent(root, group, translation(20.0, 20.0, 0.0)), "Group");
    shapes->UpdateAssemblies();
    return write(document, path);
}

} // namespace

int main(int argumentCount, char **arguments) {
    if (argumentCount != 2) {
        std::cerr << "usage: generate_fixtures <output directory>\n";
        return 1;
    }
    std::string directory = arguments[1];
    bool written = writeAssembly(directory + "/assembly.step") && writeDuplicateNames(directory + "/duplicate_names.step");
    return written ? 0 : 1;
}
