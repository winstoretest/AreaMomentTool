// AreaMomentsCommand.h: Area Moments of Inertia command class
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_AREAMOMENTS_COMMAND_H__INCLUDED_)
#define AFX_AREAMOMENTS_COMMAND_H__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include "BaseCommand.h"
#include "AreaMomentsCalculator.h"
#include "ImGuiAreaMomentsWindow.h"

class CAreaMomentsCommand : public CBaseCommand
{
public:
    CAreaMomentsCommand(BSTR sessionIdentifier);
    virtual ~CAreaMomentsCommand();

    // Override selection handling
    HRESULT __stdcall OnSelectionChange() override;

    // Override lifecycle
    HRESULT __stdcall OnTerminate() override;

private:
    // Initialize session from identifier
    bool InitializeSession();

    // Show the ImGui window
    void ShowWindow();

    // Clean up window resources
    void CleanupWindow();

    // Perform calculation for all selections
    void DoCalculate();

    // Calculate for a single face
    bool CalculateFace(ImGuiSelectionItem& item);

    // Extract mesh data from face
    bool ExtractFaceMesh(IADFacePtr pFace,
                         std::vector<double>& vertices2D,
                         std::vector<int>& indices,
                         double& perimeter);

    // Get face type name
    std::string GetFaceTypeName(IADFacePtr pFace);

    // Static callbacks
    static void OnWindowClosed(void* pContext);
    static void OnCalculateRequested(void* pContext);

    CString m_strSessionIdentifier;
    IADSessionPtr m_pSession;
    ImGuiAreaMomentsWindow* m_pWindow;
    bool m_bInitialized;
};

#endif // !defined(AFX_AREAMOMENTS_COMMAND_H__INCLUDED_)
