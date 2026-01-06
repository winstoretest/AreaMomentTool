// AreaMomentsCalculator.cpp: Area Moments of Inertia calculation utilities
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "AreaMomentsCalculator.h"

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#define new DEBUG_NEW
#endif

//////////////////////////////////////////////////////////////////////
// Public calculation methods
//////////////////////////////////////////////////////////////////////

AreaMomentsResult CAreaMomentsCalculator::Calculate(const std::vector<double>& vertices2D,
                                                     const std::vector<int>& indices)
{
    AreaMomentsResult result;

    if (vertices2D.empty() || indices.empty())
        return result;

    int numTriangles = (int)indices.size() / 3;
    if (numTriangles == 0)
        return result;

    // First pass: calculate total area and centroid
    double totalArea = 0;
    double sumCx = 0, sumCy = 0;

    for (int t = 0; t < numTriangles; t++)
    {
        int i0 = indices[t * 3];
        int i1 = indices[t * 3 + 1];
        int i2 = indices[t * 3 + 2];

        double x1 = vertices2D[i0 * 2];
        double y1 = vertices2D[i0 * 2 + 1];
        double x2 = vertices2D[i1 * 2];
        double y2 = vertices2D[i1 * 2 + 1];
        double x3 = vertices2D[i2 * 2];
        double y3 = vertices2D[i2 * 2 + 1];

        double area = SignedTriangleArea(x1, y1, x2, y2, x3, y3);

        double cx, cy;
        TriangleCentroid(x1, y1, x2, y2, x3, y3, cx, cy);

        totalArea += area;
        sumCx += area * cx;
        sumCy += area * cy;
    }

    if (fabs(totalArea) < 1e-15)
        return result;

    result.area = fabs(totalArea);
    result.Cx = sumCx / totalArea;
    result.Cy = sumCy / totalArea;

    // Second pass: calculate moments about origin, then transfer to centroid
    double Ix_origin = 0, Iy_origin = 0, Ixy_origin = 0;

    for (int t = 0; t < numTriangles; t++)
    {
        int i0 = indices[t * 3];
        int i1 = indices[t * 3 + 1];
        int i2 = indices[t * 3 + 2];

        double x1 = vertices2D[i0 * 2];
        double y1 = vertices2D[i0 * 2 + 1];
        double x2 = vertices2D[i1 * 2];
        double y2 = vertices2D[i1 * 2 + 1];
        double x3 = vertices2D[i2 * 2];
        double y3 = vertices2D[i2 * 2 + 1];

        double area = SignedTriangleArea(x1, y1, x2, y2, x3, y3);

        double Ix_tri, Iy_tri, Ixy_tri;
        TriangleMomentsAboutOrigin(x1, y1, x2, y2, x3, y3, area, Ix_tri, Iy_tri, Ixy_tri);

        Ix_origin += Ix_tri;
        Iy_origin += Iy_tri;
        Ixy_origin += Ixy_tri;
    }

    // Use parallel axis theorem to transfer to centroid
    // I_centroid = I_origin - A * d^2
    result.Ix = Ix_origin - result.area * result.Cy * result.Cy;
    result.Iy = Iy_origin - result.area * result.Cx * result.Cx;
    result.Ixy = Ixy_origin - result.area * result.Cx * result.Cy;

    // Calculate principal moments
    // I_principal = (Ix + Iy) / 2 +/- sqrt(((Ix - Iy) / 2)^2 + Ixy^2)
    double Iavg = (result.Ix + result.Iy) / 2.0;
    double Idiff = (result.Ix - result.Iy) / 2.0;
    double R = sqrt(Idiff * Idiff + result.Ixy * result.Ixy);

    result.Imax = Iavg + R;
    result.Imin = Iavg - R;

    // Principal angle (angle to max principal axis from X-axis)
    // theta = 0.5 * atan2(-2*Ixy, Ix - Iy)
    if (fabs(result.Ixy) < 1e-15 && fabs(Idiff) < 1e-15)
    {
        result.theta = 0;
    }
    else
    {
        result.theta = 0.5 * atan2(-2.0 * result.Ixy, result.Ix - result.Iy);
    }

    return result;
}

std::vector<double> CAreaMomentsCalculator::ProjectTo2D(const std::vector<double>& vertices3D,
                                                         const Vector3D& normal,
                                                         const Vector3D& origin)
{
    std::vector<double> vertices2D;

    if (vertices3D.empty())
        return vertices2D;

    int numVertices = (int)vertices3D.size() / 3;
    vertices2D.reserve(numVertices * 2);

    // Create local coordinate system on the face plane
    // Z-axis is the normal
    Vector3D zAxis = normal.Normalize();

    // X-axis: perpendicular to Z
    // Use global Y unless normal is parallel to Y, then use global X
    Vector3D globalY(0, 1, 0);
    Vector3D globalX(1, 0, 0);

    Vector3D xAxis;
    if (fabs(zAxis.Dot(globalY)) < 0.9)
    {
        xAxis = globalY.Cross(zAxis).Normalize();
    }
    else
    {
        xAxis = zAxis.Cross(globalX).Normalize();
    }

    // Y-axis completes the right-handed system
    Vector3D yAxis = zAxis.Cross(xAxis).Normalize();

    // Project each vertex to 2D
    for (int i = 0; i < numVertices; i++)
    {
        Vector3D v(vertices3D[i * 3], vertices3D[i * 3 + 1], vertices3D[i * 3 + 2]);

        // Translate to origin
        Vector3D p = v - origin;

        // Project onto local XY plane
        double x2d = p.Dot(xAxis);
        double y2d = p.Dot(yAxis);

        vertices2D.push_back(x2d);
        vertices2D.push_back(y2d);
    }

    return vertices2D;
}

Vector3D CAreaMomentsCalculator::CalculateNormal(const std::vector<double>& vertices3D,
                                                  const std::vector<int>& indices)
{
    if (indices.size() < 3 || vertices3D.size() < 9)
        return Vector3D(0, 0, 1);

    // Get first triangle
    int i0 = indices[0];
    int i1 = indices[1];
    int i2 = indices[2];

    Vector3D v0(vertices3D[i0 * 3], vertices3D[i0 * 3 + 1], vertices3D[i0 * 3 + 2]);
    Vector3D v1(vertices3D[i1 * 3], vertices3D[i1 * 3 + 1], vertices3D[i1 * 3 + 2]);
    Vector3D v2(vertices3D[i2 * 3], vertices3D[i2 * 3 + 1], vertices3D[i2 * 3 + 2]);

    Vector3D edge1 = v1 - v0;
    Vector3D edge2 = v2 - v0;

    return edge1.Cross(edge2).Normalize();
}

//////////////////////////////////////////////////////////////////////
// Private helper methods
//////////////////////////////////////////////////////////////////////

double CAreaMomentsCalculator::SignedTriangleArea(double x1, double y1, double x2, double y2, double x3, double y3)
{
    // Signed area using cross product formula
    // A = 0.5 * ((x2-x1)*(y3-y1) - (x3-x1)*(y2-y1))
    return 0.5 * ((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1));
}

void CAreaMomentsCalculator::TriangleCentroid(double x1, double y1, double x2, double y2, double x3, double y3,
                                               double& cx, double& cy)
{
    cx = (x1 + x2 + x3) / 3.0;
    cy = (y1 + y2 + y3) / 3.0;
}

void CAreaMomentsCalculator::TriangleMomentsAboutOrigin(double x1, double y1, double x2, double y2, double x3, double y3,
                                                         double area, double& Ix, double& Iy, double& Ixy)
{
    // For a triangle with signed area A:
    // Ix (about x-axis) = A/6 * (y1^2 + y2^2 + y3^2 + y1*y2 + y2*y3 + y3*y1)
    // Iy (about y-axis) = A/6 * (x1^2 + x2^2 + x3^2 + x1*x2 + x2*x3 + x3*x1)
    // Ixy = A/12 * (x1*(2*y1+y2+y3) + x2*(y1+2*y2+y3) + x3*(y1+y2+2*y3))
    //     = A/12 * (2*(x1*y1+x2*y2+x3*y3) + x1*y2+x2*y1 + x2*y3+x3*y2 + x3*y1+x1*y3)

    Ix = (area / 6.0) * (y1 * y1 + y2 * y2 + y3 * y3 + y1 * y2 + y2 * y3 + y3 * y1);

    Iy = (area / 6.0) * (x1 * x1 + x2 * x2 + x3 * x3 + x1 * x2 + x2 * x3 + x3 * x1);

    Ixy = (area / 12.0) * (x1 * (2 * y1 + y2 + y3) + x2 * (y1 + 2 * y2 + y3) + x3 * (y1 + y2 + 2 * y3));
}
