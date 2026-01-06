// ImGuiAreaMomentsWindow.h: Dear ImGui based Area Moments window
//////////////////////////////////////////////////////////////////////

#ifndef IMGUI_AREAMOMENTS_WINDOW_H
#define IMGUI_AREAMOMENTS_WINDOW_H

#include "AreaMomentsCalculator.h"
#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <d3d9.h>

// Unit types for display
enum ImGuiAreaMomentsUnits
{
    IMGUI_UNITS_CM = 0,
    IMGUI_UNITS_MM,
    IMGUI_UNITS_INCH,
    IMGUI_UNITS_COUNT
};

// Result structure
struct ImGuiAreaMomentsResult
{
    double area = 0;
    double perimeter = 0;
    double Cx = 0, Cy = 0;
    double Ixx_origin = 0, Ixy_origin = 0, Iyy_origin = 0;
    double J_origin = 0;
    double Ix_centroid = 0, Iy_centroid = 0, Ixy_centroid = 0;
    double Ix_principal = 0, Iy_principal = 0;
    double J_centroid = 0;
    double theta_deg = 0;
    double Rx = 0, Ry = 0;
    double Sx_min = 0, Sy_min = 0;
    double cx_max = 0, cy_max = 0;
    std::string faceType;
};

// Selection item
struct ImGuiSelectionItem
{
    std::string name;
    void* pFace = nullptr;  // IADFace* stored as void* to avoid namespace issues
    ImGuiAreaMomentsResult result;
    bool hasResult = false;
};

// Callback types
typedef void (*ImGuiCloseCallback)(void* pContext);
typedef void (*ImGuiCalculateCallback)(void* pContext);

class ImGuiAreaMomentsWindow
{
public:
    ImGuiAreaMomentsWindow();
    ~ImGuiAreaMomentsWindow();

    // Window lifecycle
    bool Create(HINSTANCE hInstance);
    void Destroy();
    void Show();
    void Hide();
    bool IsVisible() const;
    bool IsRunning() const;

    // Data management
    void ClearSelections();
    void AddSelection(const char* name, void* pFace);
    void SetSelectionResult(int index, const ImGuiAreaMomentsResult& result);
    int GetSelectionCount() const;

    // Callbacks
    void SetCloseCallback(ImGuiCloseCallback callback, void* pContext);
    void SetCalculateCallback(ImGuiCalculateCallback callback, void* pContext);

    // Access selections for calculation
    std::vector<ImGuiSelectionItem>& GetSelections();
    std::mutex& GetMutex();

    // Process pending requests (call from main thread)
    bool HasPendingCalculation() const { return m_calculateRequested; }
    void ClearCalculationRequest() { m_calculateRequested = false; }

    // Auto-calculate
    bool IsAutoCalculateEnabled() const { return m_autoCalculate; }

private:
    // Window procedure
    static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

    // Render thread
    void RenderThread();
    void RenderFrame();
    void RenderUI();

    // DirectX setup
    bool CreateDeviceD3D(HWND hWnd);
    void CleanupDeviceD3D();
    void ResetDevice();

    // Unit helpers
    double GetLengthFactor() const;
    double GetAreaFactor() const;
    double GetInertiaFactor() const;
    const char* GetLengthUnit() const;

    // Clipboard
    void CopyResultsToClipboard();

    // Window handles
    HWND m_hWnd = nullptr;
    HINSTANCE m_hInstance = nullptr;
    WNDCLASSEXW m_wc = {};

    // DirectX
    LPDIRECT3D9 m_pD3D = nullptr;
    LPDIRECT3DDEVICE9 m_pd3dDevice = nullptr;
    D3DPRESENT_PARAMETERS m_d3dpp = {};
    bool m_deviceLost = false;
    UINT m_resizeWidth = 0;
    UINT m_resizeHeight = 0;

    // Thread control
    std::thread m_renderThread;
    std::atomic<bool> m_running{ false };
    std::atomic<bool> m_visible{ false };
    std::atomic<bool> m_shouldClose{ false };
    std::mutex m_mutex;

    // UI state
    int m_currentUnits = IMGUI_UNITS_CM;
    int m_selectedIndex = -1;
    std::vector<ImGuiSelectionItem> m_selections;
    std::atomic<bool> m_calculateRequested{ false };
    bool m_autoCalculate = true;

    // Callbacks
    ImGuiCloseCallback m_closeCallback = nullptr;
    void* m_closeContext = nullptr;
    ImGuiCalculateCallback m_calculateCallback = nullptr;
    void* m_calculateContext = nullptr;
};

#endif // IMGUI_AREAMOMENTS_WINDOW_H
