// ImGuiAreaMomentsWindow.cpp: Dear ImGui based Area Moments window implementation
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "ImGuiAreaMomentsWindow.h"

// ImGui includes
#include "imgui/imgui.h"
#include "imgui/imgui_impl_dx9.h"
#include "imgui/imgui_impl_win32.h"

#include <cmath>

// Forward declare message handler from imgui_impl_win32.cpp
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

// Unit conversion constants
static const double CM_TO_MM = 10.0;
static const double CM_TO_INCH = 1.0 / 2.54;

// Static window pointer for WndProc
static ImGuiAreaMomentsWindow* g_pWindow = nullptr;

ImGuiAreaMomentsWindow::ImGuiAreaMomentsWindow()
{
}

ImGuiAreaMomentsWindow::~ImGuiAreaMomentsWindow()
{
    Destroy();
}

bool ImGuiAreaMomentsWindow::Create(HINSTANCE hInstance)
{
    if (m_running)
        return true;

    m_hInstance = hInstance;
    g_pWindow = this;

    // Register window class
    m_wc = {};
    m_wc.cbSize = sizeof(m_wc);
    m_wc.style = CS_CLASSDC;
    m_wc.lpfnWndProc = WndProc;
    m_wc.hInstance = hInstance;
    m_wc.lpszClassName = L"ImGuiAreaMomentsWindow";
    m_wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    ::RegisterClassExW(&m_wc);

    // Create window (larger default size, topmost so it stays visible during selection)
    m_hWnd = ::CreateWindowExW(
        WS_EX_TOPMOST,
        m_wc.lpszClassName,
        L"Area Moments of Inertia",
        WS_OVERLAPPEDWINDOW,
        100, 100, 800, 1000,
        nullptr, nullptr, hInstance, nullptr);

    if (!m_hWnd)
    {
        ::UnregisterClassW(m_wc.lpszClassName, m_hInstance);
        return false;
    }

    // Initialize Direct3D
    if (!CreateDeviceD3D(m_hWnd))
    {
        CleanupDeviceD3D();
        ::DestroyWindow(m_hWnd);
        ::UnregisterClassW(m_wc.lpszClassName, m_hInstance);
        m_hWnd = nullptr;
        return false;
    }

    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    // Setup style
    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 5.0f;
    style.FrameRounding = 3.0f;
    style.ScrollbarRounding = 3.0f;

    // Setup Platform/Renderer backends
    ImGui_ImplWin32_Init(m_hWnd);
    ImGui_ImplDX9_Init(m_pd3dDevice);

    // Load a nicer font (32pt for better readability)
    io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\segoeui.ttf", 32.0f);

    m_running = true;
    m_shouldClose = false;

    // Start render thread
    m_renderThread = std::thread(&ImGuiAreaMomentsWindow::RenderThread, this);

    return true;
}

void ImGuiAreaMomentsWindow::Destroy()
{
    if (!m_running)
        return;

    m_shouldClose = true;
    m_running = false;

    if (m_renderThread.joinable())
        m_renderThread.join();

    ImGui_ImplDX9_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    CleanupDeviceD3D();

    if (m_hWnd)
    {
        ::DestroyWindow(m_hWnd);
        m_hWnd = nullptr;
    }

    ::UnregisterClassW(m_wc.lpszClassName, m_hInstance);
    g_pWindow = nullptr;
}

void ImGuiAreaMomentsWindow::Show()
{
    if (m_hWnd)
    {
        ::ShowWindow(m_hWnd, SW_SHOW);
        ::UpdateWindow(m_hWnd);
        m_visible = true;
    }
}

void ImGuiAreaMomentsWindow::Hide()
{
    if (m_hWnd)
    {
        ::ShowWindow(m_hWnd, SW_HIDE);
        m_visible = false;
    }
}

bool ImGuiAreaMomentsWindow::IsVisible() const
{
    return m_visible;
}

bool ImGuiAreaMomentsWindow::IsRunning() const
{
    return m_running;
}

void ImGuiAreaMomentsWindow::ClearSelections()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_selections.clear();
    m_selectedIndex = -1;
}

void ImGuiAreaMomentsWindow::AddSelection(const char* name, void* pFace)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    ImGuiSelectionItem item;
    item.name = name;
    item.pFace = pFace;
    item.hasResult = false;
    m_selections.push_back(item);
}

void ImGuiAreaMomentsWindow::SetSelectionResult(int index, const ImGuiAreaMomentsResult& result)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (index >= 0 && index < (int)m_selections.size())
    {
        m_selections[index].result = result;
        m_selections[index].hasResult = true;
    }
}

int ImGuiAreaMomentsWindow::GetSelectionCount() const
{
    return (int)m_selections.size();
}

void ImGuiAreaMomentsWindow::SetCloseCallback(ImGuiCloseCallback callback, void* pContext)
{
    m_closeCallback = callback;
    m_closeContext = pContext;
}

void ImGuiAreaMomentsWindow::SetCalculateCallback(ImGuiCalculateCallback callback, void* pContext)
{
    m_calculateCallback = callback;
    m_calculateContext = pContext;
}

std::vector<ImGuiSelectionItem>& ImGuiAreaMomentsWindow::GetSelections()
{
    return m_selections;
}

std::mutex& ImGuiAreaMomentsWindow::GetMutex()
{
    return m_mutex;
}

LRESULT CALLBACK ImGuiAreaMomentsWindow::WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    switch (msg)
    {
    case WM_SIZE:
        if (wParam == SIZE_MINIMIZED)
            return 0;
        if (g_pWindow)
        {
            g_pWindow->m_resizeWidth = (UINT)LOWORD(lParam);
            g_pWindow->m_resizeHeight = (UINT)HIWORD(lParam);
        }
        return 0;

    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU)
            return 0;
        break;

    case WM_CLOSE:
        if (g_pWindow)
        {
            g_pWindow->Hide();
            if (g_pWindow->m_closeCallback)
                g_pWindow->m_closeCallback(g_pWindow->m_closeContext);
        }
        return 0;

    case WM_DESTROY:
        return 0;
    }

    return ::DefWindowProcW(hWnd, msg, wParam, lParam);
}

void ImGuiAreaMomentsWindow::RenderThread()
{
    while (!m_shouldClose)
    {
        // Process messages
        MSG msg;
        while (::PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE))
        {
            ::TranslateMessage(&msg);
            ::DispatchMessage(&msg);
        }

        if (!m_visible)
        {
            ::Sleep(50);
            continue;
        }

        // Handle device lost
        if (m_deviceLost)
        {
            HRESULT hr = m_pd3dDevice->TestCooperativeLevel();
            if (hr == D3DERR_DEVICELOST)
            {
                ::Sleep(10);
                continue;
            }
            if (hr == D3DERR_DEVICENOTRESET)
            {
                ResetDevice();
                // If still lost after reset attempt, skip rendering
                if (m_deviceLost)
                {
                    ::Sleep(10);
                    continue;
                }
            }
            m_deviceLost = false;
        }

        // Handle resize by recreating D3D device (more reliable than Reset)
        if (m_resizeWidth > 0 && m_resizeHeight > 0)
        {
            m_resizeWidth = m_resizeHeight = 0;

            // Shutdown and recreate ImGui DX9 backend with new device
            ImGui_ImplDX9_Shutdown();
            CleanupDeviceD3D();
            if (CreateDeviceD3D(m_hWnd))
            {
                ImGui_ImplDX9_Init(m_pd3dDevice);
                m_deviceLost = false;
            }
            else
            {
                m_deviceLost = true;
                ::Sleep(10);
                continue;
            }
        }

        RenderFrame();
        ::Sleep(16); // ~60 FPS
    }
}

void ImGuiAreaMomentsWindow::RenderFrame()
{
    ImGui_ImplDX9_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    RenderUI();

    ImGui::EndFrame();

    m_pd3dDevice->SetRenderState(D3DRS_ZENABLE, FALSE);
    m_pd3dDevice->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
    m_pd3dDevice->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);

    D3DCOLOR clearColor = D3DCOLOR_RGBA(45, 45, 48, 255);
    m_pd3dDevice->Clear(0, nullptr, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, clearColor, 1.0f, 0);

    if (m_pd3dDevice->BeginScene() >= 0)
    {
        ImGui::Render();
        ImGui_ImplDX9_RenderDrawData(ImGui::GetDrawData());
        m_pd3dDevice->EndScene();
    }

    HRESULT result = m_pd3dDevice->Present(nullptr, nullptr, nullptr, nullptr);
    if (result == D3DERR_DEVICELOST)
        m_deviceLost = true;
}

void ImGuiAreaMomentsWindow::RenderUI()
{
    ImGuiIO& io = ImGui::GetIO();

    // Set next window to fill the client area
    ImGui::SetNextWindowPos(ImVec2(0, 0));
    ImGui::SetNextWindowSize(io.DisplaySize);

    ImGuiWindowFlags flags = ImGuiWindowFlags_NoTitleBar |
                             ImGuiWindowFlags_NoResize |
                             ImGuiWindowFlags_NoMove |
                             ImGuiWindowFlags_NoCollapse;

    ImGui::Begin("AreaMoments", nullptr, flags);

    // Title
    ImGui::TextColored(ImVec4(0.4f, 0.8f, 1.0f, 1.0f), "Area Moments of Inertia");
    ImGui::Separator();
    ImGui::Spacing();

    // Units selector - wider dropdown
    const char* units[] = { "Centimeters (cm)", "Millimeters (mm)", "Inches (in)" };
    ImGui::SetNextItemWidth(350);
    ImGui::Combo("Units", &m_currentUnits, units, IM_ARRAYSIZE(units));
    ImGui::Spacing();

    // Auto-calculate toggle
    ImGui::Checkbox("Auto-Calculate", &m_autoCalculate);
    ImGui::Spacing();

    // Selections list (hidden when auto-calculate is on)
    if (!m_autoCalculate)
    {
        ImGui::Text("Selected Faces:");
        {
            std::lock_guard<std::mutex> lock(m_mutex);

            if (m_selections.empty())
            {
                ImGui::TextDisabled("  No faces selected");
            }
            else
            {
                ImGui::BeginChild("SelectionsList", ImVec2(0, 120), true);
                for (int i = 0; i < (int)m_selections.size(); i++)
                {
                    bool isSelected = (m_selectedIndex == i);
                    if (ImGui::Selectable(m_selections[i].name.c_str(), isSelected))
                    {
                        m_selectedIndex = i;
                    }
                }
                ImGui::EndChild();
            }
        }

        ImGui::Spacing();
    }

    ImGui::Separator();
    ImGui::Spacing();

    // Calculate height for results area (leave room for buttons at bottom)
    float buttonHeight = 50.0f;
    float buttonAreaHeight = buttonHeight + 30.0f; // button + padding
    float availableHeight = ImGui::GetContentRegionAvail().y - buttonAreaHeight;

    // Results display
    ImGui::Text("Results:");
    ImGui::BeginChild("Results", ImVec2(0, availableHeight - 30), true);

    {
        std::lock_guard<std::mutex> lock(m_mutex);

        bool hasAnyResult = false;
        for (const auto& item : m_selections)
        {
            if (item.hasResult)
            {
                hasAnyResult = true;
                break;
            }
        }

        if (!hasAnyResult)
        {
            ImGui::TextDisabled("Select faces and click Calculate.");
        }
        else
        {
            double lenFactor = GetLengthFactor();
            double areaFactor = GetAreaFactor();
            double inertiaFactor = GetInertiaFactor();
            double sectionModFactor = lenFactor * lenFactor * lenFactor;
            const char* lenUnit = GetLengthUnit();

            for (size_t i = 0; i < m_selections.size(); i++)
            {
                const auto& item = m_selections[i];
                if (!item.hasResult)
                    continue;

                const auto& r = item.result;

                if (i > 0)
                {
                    ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing();
                }

                // Header
                ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "%s", item.name.c_str());
                ImGui::Spacing();

                // Area and Centroid
                if (ImGui::TreeNodeEx("Basic Properties", ImGuiTreeNodeFlags_DefaultOpen))
                {
                    ImGui::Text("Area: %.6f %s^2", r.area * areaFactor, lenUnit);
                    ImGui::Text("Centroid: (%.6f, %.6f) %s", r.Cx * lenFactor, r.Cy * lenFactor, lenUnit);
                    ImGui::TreePop();
                }

                // First Moments
                if (ImGui::TreeNode("First Moments"))
                {
                    double Qx = r.area * r.Cy;
                    double Qy = r.area * r.Cx;
                    ImGui::Text("Qx: %.6f %s^3", Qx * sectionModFactor, lenUnit);
                    ImGui::Text("Qy: %.6f %s^3", Qy * sectionModFactor, lenUnit);
                    ImGui::TreePop();
                }

                // Second Moments about Origin
                if (ImGui::TreeNode("Second Moments (about Origin)"))
                {
                    ImGui::Text("Ixx: %.6f %s^4", r.Ixx_origin * inertiaFactor, lenUnit);
                    ImGui::Text("Iyy: %.6f %s^4", r.Iyy_origin * inertiaFactor, lenUnit);
                    ImGui::Text("Izz: %.6f %s^4", r.J_origin * inertiaFactor, lenUnit);
                    ImGui::Text("Ixy: %.6f %s^4", r.Ixy_origin * inertiaFactor, lenUnit);
                    ImGui::TreePop();
                }

                // Moments about Centroid
                if (ImGui::TreeNodeEx("Moments about Centroid", ImGuiTreeNodeFlags_DefaultOpen))
                {
                    ImGui::Text("Ix: %.6f %s^4", r.Ix_centroid * inertiaFactor, lenUnit);
                    ImGui::Text("Iy: %.6f %s^4", r.Iy_centroid * inertiaFactor, lenUnit);
                    ImGui::Text("Iz (polar): %.6f %s^4", r.J_centroid * inertiaFactor, lenUnit);
                    ImGui::Text("Ixy: %.6f %s^4", r.Ixy_centroid * inertiaFactor, lenUnit);
                    ImGui::TreePop();
                }

                // Principal Moments
                if (ImGui::TreeNodeEx("Principal Moments", ImGuiTreeNodeFlags_DefaultOpen))
                {
                    ImGui::Text("I1 (min): %.6f %s^4", r.Ix_principal * inertiaFactor, lenUnit);
                    ImGui::Text("I2 (max): %.6f %s^4", r.Iy_principal * inertiaFactor, lenUnit);
                    ImGui::Text("Principal Angle: %.2f deg", r.theta_deg);
                    ImGui::TreePop();
                }

                // Radii of Gyration
                if (ImGui::TreeNode("Radii of Gyration"))
                {
                    ImGui::Text("Rx: %.6f %s", r.Rx * lenFactor, lenUnit);
                    ImGui::Text("Ry: %.6f %s", r.Ry * lenFactor, lenUnit);
                    double Rz = (r.area > 1e-10) ? sqrt(r.J_centroid / r.area) : 0;
                    ImGui::Text("Rz: %.6f %s", Rz * lenFactor, lenUnit);
                    ImGui::TreePop();
                }

                // Section Modulus
                if (ImGui::TreeNode("Section Modulus (Elastic)"))
                {
                    ImGui::Text("Sx (Ix/c): %.6f %s^3", r.Sx_min * sectionModFactor, lenUnit);
                    ImGui::Text("Sy (Iy/c): %.6f %s^3", r.Sy_min * sectionModFactor, lenUnit);
                    ImGui::TreePop();
                }
            }
        }
    }

    ImGui::EndChild();

    // Buttons at the bottom
    ImGui::Spacing();

    float buttonWidth = 150.0f;

    // Hide Calculate button when auto-calculate is on
    if (!m_autoCalculate)
    {
        if (ImGui::Button("Calculate", ImVec2(buttonWidth, buttonHeight)))
        {
            m_calculateRequested = true;
            if (m_calculateCallback)
                m_calculateCallback(m_calculateContext);
        }
        ImGui::SameLine();
    }
    if (ImGui::Button("Copy Results", ImVec2(buttonWidth, buttonHeight)))
    {
        CopyResultsToClipboard();
    }
    ImGui::SameLine();
    if (ImGui::Button("Close", ImVec2(buttonWidth, buttonHeight)))
    {
        Hide();
        if (m_closeCallback)
            m_closeCallback(m_closeContext);
    }

    ImGui::End();
}

bool ImGuiAreaMomentsWindow::CreateDeviceD3D(HWND hWnd)
{
    m_pD3D = Direct3DCreate9(D3D_SDK_VERSION);
    if (!m_pD3D)
        return false;

    ZeroMemory(&m_d3dpp, sizeof(m_d3dpp));
    m_d3dpp.Windowed = TRUE;
    m_d3dpp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    m_d3dpp.BackBufferFormat = D3DFMT_UNKNOWN;
    m_d3dpp.EnableAutoDepthStencil = TRUE;
    m_d3dpp.AutoDepthStencilFormat = D3DFMT_D16;
    m_d3dpp.PresentationInterval = D3DPRESENT_INTERVAL_ONE;

    // Use multithreaded flag since we render from a separate thread
    DWORD behaviorFlags = D3DCREATE_HARDWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED;
    if (m_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
        behaviorFlags, &m_d3dpp, &m_pd3dDevice) < 0)
    {
        // Fallback to software vertex processing
        behaviorFlags = D3DCREATE_SOFTWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED;
        if (m_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
            behaviorFlags, &m_d3dpp, &m_pd3dDevice) < 0)
            return false;
    }

    return true;
}

void ImGuiAreaMomentsWindow::CleanupDeviceD3D()
{
    if (m_pd3dDevice)
    {
        m_pd3dDevice->Release();
        m_pd3dDevice = nullptr;
    }
    if (m_pD3D)
    {
        m_pD3D->Release();
        m_pD3D = nullptr;
    }
}

void ImGuiAreaMomentsWindow::ResetDevice()
{
    // For windowed mode, 0 means use window client area - this is valid
    ImGui_ImplDX9_InvalidateDeviceObjects();
    HRESULT hr = m_pd3dDevice->Reset(&m_d3dpp);
    if (SUCCEEDED(hr))
    {
        ImGui_ImplDX9_CreateDeviceObjects();
        m_deviceLost = false;
    }
    else
    {
        // Reset failed, mark device as lost to retry later
        m_deviceLost = true;
    }
}

double ImGuiAreaMomentsWindow::GetLengthFactor() const
{
    switch (m_currentUnits)
    {
    case IMGUI_UNITS_MM:   return CM_TO_MM;
    case IMGUI_UNITS_INCH: return CM_TO_INCH;
    default:               return 1.0;
    }
}

double ImGuiAreaMomentsWindow::GetAreaFactor() const
{
    double len = GetLengthFactor();
    return len * len;
}

double ImGuiAreaMomentsWindow::GetInertiaFactor() const
{
    double len = GetLengthFactor();
    return len * len * len * len;
}

const char* ImGuiAreaMomentsWindow::GetLengthUnit() const
{
    switch (m_currentUnits)
    {
    case IMGUI_UNITS_MM:   return "mm";
    case IMGUI_UNITS_INCH: return "in";
    default:               return "cm";
    }
}

void ImGuiAreaMomentsWindow::CopyResultsToClipboard()
{
    std::lock_guard<std::mutex> lock(m_mutex);

    std::string text;
    text += "Area Moments of Inertia Results\n";
    text += "================================\n\n";

    double lenFactor = GetLengthFactor();
    double areaFactor = GetAreaFactor();
    double inertiaFactor = GetInertiaFactor();
    double sectionModFactor = lenFactor * lenFactor * lenFactor;
    const char* lenUnit = GetLengthUnit();

    for (size_t i = 0; i < m_selections.size(); i++)
    {
        const auto& item = m_selections[i];
        if (!item.hasResult)
            continue;

        const auto& r = item.result;

        text += item.name + "\n";
        text += std::string(item.name.length(), '-') + "\n\n";

        // Basic Properties
        text += "Basic Properties:\n";
        char buf[256];
        sprintf_s(buf, "  Area: %.6f %s^2\n", r.area * areaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Centroid: (%.6f, %.6f) %s\n\n", r.Cx * lenFactor, r.Cy * lenFactor, lenUnit);
        text += buf;

        // First Moments
        double Qx = r.area * r.Cy;
        double Qy = r.area * r.Cx;
        text += "First Moments:\n";
        sprintf_s(buf, "  Qx: %.6f %s^3\n", Qx * sectionModFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Qy: %.6f %s^3\n\n", Qy * sectionModFactor, lenUnit);
        text += buf;

        // Second Moments about Origin
        text += "Second Moments (about Origin):\n";
        sprintf_s(buf, "  Ixx: %.6f %s^4\n", r.Ixx_origin * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Iyy: %.6f %s^4\n", r.Iyy_origin * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Izz: %.6f %s^4\n", r.J_origin * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Ixy: %.6f %s^4\n\n", r.Ixy_origin * inertiaFactor, lenUnit);
        text += buf;

        // Moments about Centroid
        text += "Moments about Centroid:\n";
        sprintf_s(buf, "  Ix: %.6f %s^4\n", r.Ix_centroid * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Iy: %.6f %s^4\n", r.Iy_centroid * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Iz (polar): %.6f %s^4\n", r.J_centroid * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Ixy: %.6f %s^4\n\n", r.Ixy_centroid * inertiaFactor, lenUnit);
        text += buf;

        // Principal Moments
        text += "Principal Moments:\n";
        sprintf_s(buf, "  I1 (min): %.6f %s^4\n", r.Ix_principal * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  I2 (max): %.6f %s^4\n", r.Iy_principal * inertiaFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Principal Angle: %.2f deg\n\n", r.theta_deg);
        text += buf;

        // Radii of Gyration
        text += "Radii of Gyration:\n";
        sprintf_s(buf, "  Rx: %.6f %s\n", r.Rx * lenFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Ry: %.6f %s\n", r.Ry * lenFactor, lenUnit);
        text += buf;
        double Rz = (r.area > 1e-10) ? sqrt(r.J_centroid / r.area) : 0;
        sprintf_s(buf, "  Rz: %.6f %s\n\n", Rz * lenFactor, lenUnit);
        text += buf;

        // Section Modulus
        text += "Section Modulus (Elastic):\n";
        sprintf_s(buf, "  Sx (Ix/c): %.6f %s^3\n", r.Sx_min * sectionModFactor, lenUnit);
        text += buf;
        sprintf_s(buf, "  Sy (Iy/c): %.6f %s^3\n", r.Sy_min * sectionModFactor, lenUnit);
        text += buf;

        text += "\n";
    }

    // Copy to clipboard using Windows API
    if (OpenClipboard(m_hWnd))
    {
        EmptyClipboard();

        size_t len = text.length() + 1;
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, len);
        if (hMem)
        {
            char* pMem = (char*)GlobalLock(hMem);
            if (pMem)
            {
                memcpy(pMem, text.c_str(), len);
                GlobalUnlock(hMem);
                SetClipboardData(CF_TEXT, hMem);
            }
        }

        CloseClipboard();
    }
}
