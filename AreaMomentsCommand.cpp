// AreaMomentsCommand.cpp: Area Moments of Inertia command implementation
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "MyAlibreAddOn.h"
#include "AreaMomentsCommand.h"
#include <cmath>

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#define new DEBUG_NEW
#endif

// Access to the application object for IADRoot
extern CMyAlibreAddOnApp theApp;

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CAreaMomentsCommand::CAreaMomentsCommand(BSTR sessionIdentifier)
    : CBaseCommand()
    , m_strSessionIdentifier(sessionIdentifier)
    , m_pSession(nullptr)
    , m_pWindow(nullptr)
    , m_bInitialized(false)
{
}

CAreaMomentsCommand::~CAreaMomentsCommand()
{
    CleanupWindow();
    m_pSession = nullptr;
}

void CAreaMomentsCommand::CleanupWindow()
{
    if (m_pWindow != nullptr)
    {
        m_pWindow->SetCloseCallback(nullptr, nullptr);
        m_pWindow->SetCalculateCallback(nullptr, nullptr);
        m_pWindow->Destroy();
        delete m_pWindow;
        m_pWindow = nullptr;
    }
}

// Static callback when window closes
void CAreaMomentsCommand::OnWindowClosed(void* pContext)
{
    CAreaMomentsCommand* pThis = static_cast<CAreaMomentsCommand*>(pContext);
    if (pThis != nullptr && pThis->m_pCommandSite != nullptr)
    {
        pThis->m_pCommandSite->Terminate();
    }
}

// Static callback when calculate is requested
void CAreaMomentsCommand::OnCalculateRequested(void* pContext)
{
    CAreaMomentsCommand* pThis = static_cast<CAreaMomentsCommand*>(pContext);
    if (pThis != nullptr)
    {
        pThis->DoCalculate();
    }
}

//////////////////////////////////////////////////////////////////////
// Session initialization
//////////////////////////////////////////////////////////////////////

bool CAreaMomentsCommand::InitializeSession()
{
    if (m_bInitialized)
        return (m_pSession != nullptr);

    m_bInitialized = true;

    try
    {
        if (theApp.m_pRoot == nullptr)
            return false;

        // Get sessions collection
        IADSessionsPtr pSessions = theApp.m_pRoot->GetSessions();
        if (pSessions == nullptr)
            return false;

        // Find session by identifier
        long count = pSessions->GetCount();
        for (long i = 0; i < count; i++)
        {
            IADSessionPtr pSession = pSessions->GetItem(_variant_t(i));
            if (pSession != nullptr)
            {
                _bstr_t identifier = pSession->GetIdentifier();
                if (m_strSessionIdentifier.Compare((LPCTSTR)identifier) == 0)
                {
                    m_pSession = pSession;
                    return true;
                }
            }
        }
    }
    catch (_com_error& e)
    {
        CString msg;
        msg.Format(_T("Error initializing session: %s"), (LPCTSTR)e.Description());
        AfxMessageBox(msg);
    }

    return false;
}

//////////////////////////////////////////////////////////////////////
// Window handling
//////////////////////////////////////////////////////////////////////

void CAreaMomentsCommand::ShowWindow()
{
    if (m_pWindow == nullptr)
    {
        m_pWindow = new ImGuiAreaMomentsWindow();
        if (!m_pWindow->Create(AfxGetInstanceHandle()))
        {
            delete m_pWindow;
            m_pWindow = nullptr;
            AfxMessageBox(_T("Failed to create ImGui window."));
            return;
        }
        m_pWindow->SetCloseCallback(OnWindowClosed, this);
        m_pWindow->SetCalculateCallback(OnCalculateRequested, this);
    }

    if (!m_pWindow->IsVisible())
    {
        m_pWindow->Show();
    }
}

//////////////////////////////////////////////////////////////////////
// Selection handling
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CAreaMomentsCommand::OnSelectionChange()
{
    AFX_MANAGE_STATE(AfxGetStaticModuleState());

    try
    {
        // Initialize session if needed
        if (!InitializeSession())
        {
            AfxMessageBox(_T("Unable to access the current session."));
            return S_OK;
        }

        // Show window if not already shown
        ShowWindow();

        if (m_pWindow == nullptr || m_pSession == nullptr)
            return S_OK;

        // Clear and update selections
        m_pWindow->ClearSelections();

        // Get selected objects from session
        IObjectCollectorPtr pSelected = m_pSession->GetSelectedObjects();
        if (pSelected == nullptr)
            return S_OK;

        long count = pSelected->GetCount();
        int faceIndex = 1;

        for (long i = 0; i < count; i++)
        {
            IDispatchPtr pObj = pSelected->GetItem(_variant_t(i));
            if (pObj == nullptr)
                continue;

            try
            {
                IADTargetProxyPtr pProxy = pObj;
                if (pProxy != nullptr)
                {
                    IDispatchPtr pTarget = pProxy->GetTarget();
                    if (pTarget != nullptr)
                    {
                        IADFacePtr pFace = pTarget;
                        if (pFace != nullptr)
                        {
                            std::string typeName = GetFaceTypeName(pFace);
                            char nameBuf[128];
                            sprintf_s(nameBuf, "%s %d", typeName.c_str(), faceIndex++);
                            m_pWindow->AddSelection(nameBuf, (void*)pFace.GetInterfacePtr());
                        }
                    }
                }
            }
            catch (_com_error&)
            {
                // Not a face, skip
            }
        }
    }
    catch (_com_error& e)
    {
        CString msg;
        msg.Format(_T("Error processing selection: %s"), (LPCTSTR)e.Description());
        AfxMessageBox(msg);
    }
    catch (...)
    {
        AfxMessageBox(_T("Unknown error occurred while processing selection."));
    }

    // Auto-calculate if enabled
    if (m_pWindow != nullptr && m_pWindow->IsAutoCalculateEnabled())
    {
        DoCalculate();
    }

    return S_OK;
}

//////////////////////////////////////////////////////////////////////
// Calculation
//////////////////////////////////////////////////////////////////////

void CAreaMomentsCommand::DoCalculate()
{
    if (m_pWindow == nullptr)
        return;

    std::lock_guard<std::mutex> lock(m_pWindow->GetMutex());
    auto& selections = m_pWindow->GetSelections();

    for (size_t i = 0; i < selections.size(); i++)
    {
        if (!selections[i].hasResult)
        {
            CalculateFace(selections[i]);
        }
    }
}

bool CAreaMomentsCommand::CalculateFace(ImGuiSelectionItem& item)
{
    if (item.pFace == nullptr)
        return false;

    IADFacePtr pFace((AlibreX::IADFace*)item.pFace);

    std::vector<double> vertices2D;
    std::vector<int> indices;
    double perimeter = 0;

    if (!ExtractFaceMesh(pFace, vertices2D, indices, perimeter))
        return false;

    // Calculate basic area moments
    AreaMomentsResult basicResult = CAreaMomentsCalculator::Calculate(vertices2D, indices);

    // Fill in full result
    ImGuiAreaMomentsResult& r = item.result;
    r.area = basicResult.area;
    r.perimeter = perimeter;
    r.Cx = basicResult.Cx;
    r.Cy = basicResult.Cy;

    // Inertia about origin (using parallel axis theorem)
    r.Ixx_origin = basicResult.Ix + r.area * r.Cy * r.Cy;
    r.Iyy_origin = basicResult.Iy + r.area * r.Cx * r.Cx;
    r.Ixy_origin = basicResult.Ixy + r.area * r.Cx * r.Cy;

    // Polar moments
    r.J_origin = r.Ixx_origin + r.Iyy_origin;
    r.J_centroid = basicResult.Ix + basicResult.Iy;

    // Moments about centroid
    r.Ix_centroid = basicResult.Ix;
    r.Iy_centroid = basicResult.Iy;
    r.Ixy_centroid = basicResult.Ixy;

    // Principal moments
    r.Ix_principal = basicResult.Imin;
    r.Iy_principal = basicResult.Imax;

    // Rotation angle
    r.theta_deg = basicResult.theta * 180.0 / 3.14159265358979323846;

    // Radii of gyration
    if (r.area > 1e-10)
    {
        r.Rx = sqrt(basicResult.Ix / r.area);
        r.Ry = sqrt(basicResult.Iy / r.area);
    }

    // Calculate extreme fiber distances from centroid
    r.cx_max = 0;
    r.cy_max = 0;
    for (size_t i = 0; i < vertices2D.size(); i += 2)
    {
        double dx = fabs(vertices2D[i] - r.Cx);
        double dy = fabs(vertices2D[i + 1] - r.Cy);
        if (dx > r.cx_max) r.cx_max = dx;
        if (dy > r.cy_max) r.cy_max = dy;
    }

    // Section modulus
    if (r.cy_max > 1e-10)
        r.Sx_min = basicResult.Ix / r.cy_max;
    if (r.cx_max > 1e-10)
        r.Sy_min = basicResult.Iy / r.cx_max;

    // Face type
    r.faceType = GetFaceTypeName(pFace);

    item.hasResult = true;
    return true;
}

bool CAreaMomentsCommand::ExtractFaceMesh(IADFacePtr pFace,
                                          std::vector<double>& vertices2D,
                                          std::vector<int>& indices,
                                          double& perimeter)
{
    if (pFace == nullptr)
        return false;

    perimeter = 0;

    try
    {
        double surfaceTol = 0.001;
        SAFEARRAY* pFacetData = pFace->FacetData(surfaceTol);
        if (pFacetData == nullptr)
            return false;

        double* pData = nullptr;
        HRESULT hr = SafeArrayAccessData(pFacetData, (void**)&pData);
        if (FAILED(hr) || pData == nullptr)
        {
            SafeArrayDestroy(pFacetData);
            return false;
        }

        long lBound, uBound;
        SafeArrayGetLBound(pFacetData, 1, &lBound);
        SafeArrayGetUBound(pFacetData, 1, &uBound);
        long dataSize = uBound - lBound + 1;

        if (dataSize < 10)
        {
            SafeArrayUnaccessData(pFacetData);
            SafeArrayDestroy(pFacetData);
            return false;
        }

        int numTriangles = (int)(dataSize / 9);
        if (numTriangles <= 0)
        {
            SafeArrayUnaccessData(pFacetData);
            SafeArrayDestroy(pFacetData);
            return false;
        }

        std::vector<double> vertices3D;
        vertices3D.reserve(numTriangles * 9);
        indices.reserve(numTriangles * 3);

        int vertexIndex = 0;
        for (int t = 0; t < numTriangles; t++)
        {
            int offset = t * 9;
            for (int v = 0; v < 3; v++)
            {
                vertices3D.push_back((double)pData[offset + v * 3]);
                vertices3D.push_back((double)pData[offset + v * 3 + 1]);
                vertices3D.push_back((double)pData[offset + v * 3 + 2]);
                indices.push_back(vertexIndex++);
            }
        }

        SafeArrayUnaccessData(pFacetData);
        SafeArrayDestroy(pFacetData);

        Vector3D normal = CAreaMomentsCalculator::CalculateNormal(vertices3D, indices);
        Vector3D origin(vertices3D[0], vertices3D[1], vertices3D[2]);
        vertices2D = CAreaMomentsCalculator::ProjectTo2D(vertices3D, normal, origin);

        return !vertices2D.empty();
    }
    catch (_com_error& e)
    {
        CString msg;
        msg.Format(_T("COM Error: %s"), (LPCTSTR)e.Description());
        TRACE("%s\n", msg);
        return false;
    }
    catch (...)
    {
        return false;
    }
}

std::string CAreaMomentsCommand::GetFaceTypeName(IADFacePtr pFace)
{
    if (pFace == nullptr)
        return "Face";

    try
    {
        IADSurfacePtr pSurface = pFace->GetGeometry();
        if (pSurface != nullptr)
        {
            enum ADGeometryType surfType = pSurface->GetSurfaceType();
            switch (surfType)
            {
            case ADGeometryType_AD_PLANE:    return "Planar Face";
            case ADGeometryType_AD_CYLINDER: return "Cylindrical Face";
            case ADGeometryType_AD_CONE:     return "Conical Face";
            case ADGeometryType_AD_SPHERE:   return "Spherical Face";
            case ADGeometryType_AD_TORUS:    return "Toroidal Face";
            case ADGeometryType_AD_BSURF:    return "B-Spline Surface";
            default:                          return "Face";
            }
        }
    }
    catch (...)
    {
    }

    return "Face";
}

//////////////////////////////////////////////////////////////////////
// Lifecycle
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CAreaMomentsCommand::OnTerminate()
{
    AFX_MANAGE_STATE(AfxGetStaticModuleState());

    CleanupWindow();

    m_pSession = nullptr;
    m_bInitialized = false;

    return CBaseCommand::OnTerminate();
}
