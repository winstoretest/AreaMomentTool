// BaseCommand.h: interface for the CBaseCommand class.
// Base command template for Alibre AddOn commands
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_BASECOMMAND_H__INCLUDED_)
#define AFX_BASECOMMAND_H__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

class CBaseCommand : public IAlibreAddOnCommand
{
public:
	CBaseCommand();
	virtual ~CBaseCommand();

public:
	// IUnknown
	HRESULT __stdcall QueryInterface(REFIID riid, void **ppObj);
	ULONG __stdcall AddRef();
	ULONG __stdcall Release();

	// IDispatch
	HRESULT __stdcall GetTypeInfoCount(UINT FAR* pctinfo);
	HRESULT __stdcall GetTypeInfo(UINT iTInfo, LCID lcid, ITypeInfo FAR* FAR* ppTInfo);
	HRESULT __stdcall GetIDsOfNames(REFIID riid, OLECHAR FAR* FAR* rgszNames, UINT cNames, LCID lcid, DISPID FAR* rgDispId);
	HRESULT __stdcall Invoke(DISPID dispidMember, REFIID riid, LCID lcid, WORD wFlags, DISPPARAMS FAR* pDispParams, VARIANT FAR* pVarResult, EXCEPINFO FAR* pExcepInfo, UINT FAR* puArgErr);

	// IAlibreAddOnCommand - CommandSite property
	HRESULT __stdcall putref_CommandSite(struct IADAddOnCommandSite* pRetVal);
	HRESULT __stdcall get_CommandSite(struct IADAddOnCommandSite** pRetVal);

	// IAlibreAddOnCommand - Toggle and Tab
	HRESULT __stdcall IsTwoWayToggle(VARIANT_BOOL* pRetVal);
	HRESULT __stdcall AddTab(VARIANT_BOOL* pRetVal);
	HRESULT __stdcall get_TabName(BSTR* pRetVal);

	// IAlibreAddOnCommand - UI
	HRESULT __stdcall OnShowUI(__int64 hWnd);

	// IAlibreAddOnCommand - Rendering
	HRESULT __stdcall OnRender(long hDC, long clipRectX, long clipRectY, long clipRectWidth, long clipRectHeight);
	HRESULT __stdcall On3DRender();
	HRESULT __stdcall get_Extents(SAFEARRAY** pRetVal);

	// IAlibreAddOnCommand - Mouse events
	HRESULT __stdcall OnClick(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnDoubleClick(long screenX, long screenY, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnMouseDown(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnMouseMove(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnMouseUp(long screenX, long screenY, enum ADDONMouseButtons buttons, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnMouseWheel(double delta, VARIANT_BOOL* pRetVal);

	// IAlibreAddOnCommand - Keyboard events
	HRESULT __stdcall OnKeyDown(long keycode, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnKeyUp(long keycode, VARIANT_BOOL* pRetVal);
	HRESULT __stdcall OnEscape(VARIANT_BOOL* pRetVal);

	// IAlibreAddOnCommand - Selection and lifecycle
	HRESULT __stdcall OnSelectionChange();
	HRESULT __stdcall OnTerminate();
	HRESULT __stdcall OnComplete();

protected:
	IADAddOnCommandSitePtr m_pCommandSite;

private:
	long m_nRefCount;
};

#endif // !defined(AFX_BASECOMMAND_H__INCLUDED_)
