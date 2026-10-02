// Plain C interface over OpenCASCADE's STEP reader. All lengths are meters (SI); the
// conversion from the file's units happens on the C++ side.
#ifndef LIBRA_STEP_BRIDGE_H
#define LIBRA_STEP_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double x, y, z;
} LibraStepVector;

typedef enum {
    LibraStepFaceOther = 0,
    LibraStepFacePlane = 1,
    LibraStepFaceCylinder = 2,
    LibraStepFaceCone = 3,
    LibraStepFaceSphere = 4,
    LibraStepFaceTorus = 5
} LibraStepFaceKind;

typedef struct {
    int32_t kind;               // LibraStepFaceKind
    LibraStepVector center;     // plane: area centroid; cylinder/cone/torus: point on axis; sphere: center
    LibraStepVector direction;  // plane: outward normal; cylinder/cone/torus: axis direction
    double radius;              // cylinder/sphere radius, cone reference radius, torus major radius
    int32_t triangleStart;      // triangles of this face are contiguous in `indices`
    int32_t triangleCount;
    int32_t edgeStart;          // range into `faceEdges`
    int32_t edgeCount;
} LibraStepFace;

typedef enum {
    LibraStepEdgeOther = 0,
    LibraStepEdgeLine = 1,
    LibraStepEdgeCircle = 2
} LibraStepEdgeKind;

typedef struct {
    int32_t kind;               // LibraStepEdgeKind
    LibraStepVector center;     // circle center
    LibraStepVector direction;  // line: direction; circle: axis normal
    double radius;
    int32_t pointStart;         // range into `edgePoints` (in points, not floats)
    int32_t pointCount;
} LibraStepEdge;

typedef struct {
    const char *name;            // instance name, e.g. "Hub v3:1"
    const char *definitionName;  // shared by all instances of the same component, e.g. "Hub v3"
    const char *path;            // names of enclosing assemblies, root first, separated by '\x1f'
    int32_t hasColor;
    float color[3];

    // Exact properties at unit density (1 kg/m³), world axes. Inertia is about the centroid.
    double volume;
    LibraStepVector centroid;
    double inertia[9];           // row-major 3x3

    // Render mesh in world coordinates
    const float *positions;      // xyz per vertex
    const float *normals;        // xyz per vertex
    int32_t vertexCount;
    const uint32_t *indices;     // 3 per triangle, grouped by face
    int32_t triangleCount;

    const LibraStepFace *faces;
    int32_t faceCount;
    const int32_t *faceEdges;
    int32_t faceEdgeCount;
    const LibraStepEdge *edges;
    int32_t edgeCount;
    const float *edgePoints;     // xyz per point
    int32_t edgePointCount;
    const float *vertices;       // xyz per topological vertex
    int32_t vertexPointCount;
} LibraStepPart;

typedef struct {
    const char *errorMessage;    // NULL on success
    const LibraStepPart *parts;
    int32_t partCount;
    void *storage;               // owned by the bridge
} LibraStepResult;

/// Reads a STEP file. Always returns a result (check errorMessage); free it with libra_step_free.
/// Not thread safe: call from one thread at a time.
LibraStepResult *libra_step_import(const char *path);
void libra_step_free(LibraStepResult *result);

#ifdef __cplusplus
}
#endif

#endif
