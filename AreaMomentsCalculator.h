// AreaMomentsCalculator.h: Area Moments of Inertia calculation utilities
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_AREOMOMENTSCALCULATOR_H__INCLUDED_)
#define AFX_AREOMOMENTSCALCULATOR_H__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include <vector>
#include <cmath>

// Result structure for area moment calculations
struct AreaMomentsResult {
    double area;           // Total area
    double Cx, Cy;         // Centroid coordinates (in local 2D plane)
    double Ix, Iy;         // Second moments of area about centroidal axes
    double Ixy;            // Product of inertia about centroidal axes
    double Imin, Imax;     // Principal moments of inertia
    double theta;          // Principal axis angle (radians from X-axis)

    AreaMomentsResult() : area(0), Cx(0), Cy(0), Ix(0), Iy(0), Ixy(0), Imin(0), Imax(0), theta(0) {}
};

// 3D Vector structure for coordinate transformations
struct Vector3D {
    double x, y, z;

    Vector3D() : x(0), y(0), z(0) {}
    Vector3D(double _x, double _y, double _z) : x(_x), y(_y), z(_z) {}

    Vector3D operator-(const Vector3D& v) const { return Vector3D(x - v.x, y - v.y, z - v.z); }
    Vector3D operator+(const Vector3D& v) const { return Vector3D(x + v.x, y + v.y, z + v.z); }
    Vector3D operator*(double s) const { return Vector3D(x * s, y * s, z * s); }

    double Dot(const Vector3D& v) const { return x * v.x + y * v.y + z * v.z; }

    Vector3D Cross(const Vector3D& v) const {
        return Vector3D(
            y * v.z - z * v.y,
            z * v.x - x * v.z,
            x * v.y - y * v.x
        );
    }

    double Length() const { return sqrt(x * x + y * y + z * z); }

    Vector3D Normalize() const {
        double len = Length();
        if (len > 1e-10)
            return Vector3D(x / len, y / len, z / len);
        return Vector3D(0, 0, 0);
    }
};

class CAreaMomentsCalculator
{
public:
    // Calculate area moments from 2D triangulated mesh
    // vertices: array of 2D coordinates [x0, y0, x1, y1, x2, y2, ...]
    // indices: array of triangle indices [i0, i1, i2, i3, i4, i5, ...] (3 per triangle)
    static AreaMomentsResult Calculate(const std::vector<double>& vertices2D,
                                        const std::vector<int>& indices);

    // Project 3D vertices to 2D local coordinate system on face plane
    // vertices3D: array of 3D coordinates [x0, y0, z0, x1, y1, z1, ...]
    // normal: face normal vector
    // origin: point on face to use as origin
    // Returns: 2D coordinates in local plane
    static std::vector<double> ProjectTo2D(const std::vector<double>& vertices3D,
                                            const Vector3D& normal,
                                            const Vector3D& origin);

    // Calculate face normal from first triangle
    static Vector3D CalculateNormal(const std::vector<double>& vertices3D,
                                     const std::vector<int>& indices);

private:
    // Calculate signed area of triangle (for proper handling of orientation)
    static double SignedTriangleArea(double x1, double y1, double x2, double y2, double x3, double y3);

    // Calculate triangle centroid
    static void TriangleCentroid(double x1, double y1, double x2, double y2, double x3, double y3,
                                  double& cx, double& cy);

    // Calculate second moments of triangle about origin
    // Using formulas: Ix = A/6 * (y1^2 + y2^2 + y3^2 + y1*y2 + y2*y3 + y3*y1)
    //                 Iy = A/6 * (x1^2 + x2^2 + x3^2 + x1*x2 + x2*x3 + x3*x1)
    //                 Ixy = A/12 * (x1*(2*y1+y2+y3) + x2*(y1+2*y2+y3) + x3*(y1+y2+2*y3))
    static void TriangleMomentsAboutOrigin(double x1, double y1, double x2, double y2, double x3, double y3,
                                            double area, double& Ix, double& Iy, double& Ixy);
};

#endif // !defined(AFX_AREOMOMENTSCALCULATOR_H__INCLUDED_)
