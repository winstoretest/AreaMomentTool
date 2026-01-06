// BaseCommand.cpp: implementation of the CBaseCommand class.
// Base command template for Alibre AddOn commands
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "MyAlibreAddOn.h"
#include "BaseCommand.h"

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[]=__FILE__;
#define new DEBUG_NEW
#endif

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CBaseCommand::CBaseCommand()
{
	m_nRefCount = 0;
	m_pCommandSite = NULL;
}

CBaseCommand::~CBaseCommand()
{
	m_pCommandSite = NULL;
}

//////////////////////////////////////////////////////////////////////
// IUnknown implementation
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::QueryInterface(REFIID riid, void **ppObj)
{
	if (riid == IID_IUnknown)
	{
		*ppObj = static_cast<IUnknown*>(this);
		AddRef();
		return S_OK;
	}

	if (riid == __uuidof(IAlibreAddOnCommand))
	{
		*ppObj = static_cast<IAlibreAddOnCommand*>(this);
		AddRef();
		return S_OK;
	}

	*ppObj = NULL;
	return E_NOINTERFACE;
}

ULONG __stdcall CBaseCommand::AddRef()
{
	return InterlockedIncrement(&m_nRefCount);
}

ULONG __stdcall CBaseCommand::Release()
{
	long nRefCount = InterlockedDecrement(&m_nRefCount);
	if (nRefCount == 0)
	{
		delete this;
	}
	return nRefCount;
}

//////////////////////////////////////////////////////////////////////
// IDispatch implementation
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::GetTypeInfoCount(UINT FAR* pctinfo)
{
	*pctinfo = 0;
	return S_OK;
}

HRESULT __stdcall CBaseCommand::GetTypeInfo(UINT iTInfo, LCID lcid, ITypeInfo FAR* FAR* ppTInfo)
{
	*ppTInfo = NULL;
	return E_NOTIMPL;
}

HRESULT __stdcall CBaseCommand::GetIDsOfNames(REFIID riid, OLECHAR FAR* FAR* rgszNames, UINT cNames, LCID lcid, DISPID FAR* rgDispId)
{
	return E_NOTIMPL;
}

HRESULT __stdcall CBaseCommand::Invoke(DISPID dispidMember, REFIID riid, LCID lcid, WORD wFlags, DISPPARAMS FAR* pDispParams, VARIANT FAR* pVarResult, EXCEPINFO FAR* pExcepInfo, UINT FAR* puArgErr)
{
	return E_NOTIMPL;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - CommandSite property
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::putref_CommandSite(struct IADAddOnCommandSite* pRetVal)
{
	m_pCommandSite = pRetVal;
	return S_OK;
}

HRESULT __stdcall CBaseCommand::get_CommandSite(struct IADAddOnCommandSite** pRetVal)
{
	*pRetVal = m_pCommandSite;
	if (m_pCommandSite)
		m_pCommandSite->AddRef();
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - Toggle and Tab
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::IsTwoWayToggle(VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE;
	return S_OK;
}

HRESULT __stdcall CBaseCommand::AddTab(VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE;
	return S_OK;
}

HRESULT __stdcall CBaseCommand::get_TabName(BSTR* pRetVal)
{
	*pRetVal = NULL;
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - UI
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::OnShowUI(__int64 hWnd)
{
	// Show custom UI here if needed
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - Rendering
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::OnRender(long hDC, long clipRectX, long clipRectY, long clipRectWidth, long clipRectHeight)
{
	// Custom 2D rendering goes here
	return S_OK;
}

HRESULT __stdcall CBaseCommand::On3DRender()
{
	// Custom 3D rendering goes here
	return S_OK;
}

HRESULT __stdcall CBaseCommand::get_Extents(SAFEARRAY** pRetVal)
{
	*pRetVal = NULL;
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - Mouse events
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::OnClick(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnDoubleClick(long screenX, long screenY, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnMouseDown(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnMouseMove(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnMouseUp(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnMouseWheel(double delta, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - Keyboard events
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::OnKeyDown(long keycode, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnKeyUp(long keycode, VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnEscape(VARIANT_BOOL* pRetVal)
{
	*pRetVal = VARIANT_FALSE; // Not handled - let Alibre handle escape
	return S_OK;
}

//////////////////////////////////////////////////////////////////////
// IAlibreAddOnCommand - Selection and lifecycle
//////////////////////////////////////////////////////////////////////

HRESULT __stdcall CBaseCommand::OnSelectionChange()
{
	// Handle selection changes here
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnTerminate()
{
	// Clean up when command terminates
	return S_OK;
}

HRESULT __stdcall CBaseCommand::OnComplete()
{
	// Called when command completes
	return S_OK;
}
