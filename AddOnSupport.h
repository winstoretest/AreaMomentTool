#ifndef __ADDONSUPPORT_H__
#define __ADDONSUPPORT_H__


//#include <d3dx9.h>

const int		nMAIN_MENUS_COUNT					= 1;
const int		nROOT_MENU_ID						= 100;
const int		nAREA_MOMENTS_MENU_ID				= 101;

const CString	cStrROOT_MENU						= "Area Moments";
const CString	cStrAREA_MOMENTS_MENU				= "Calculate Area Moments...";

template<typename T> HRESULT getSafeArrayFromArray (/*IN*/ T* pIntBuffer,
							   /*IN*/ long size,
							   /*IN*/ enum VARENUM VT_Size,
							   /*OUT*/SAFEARRAY** ppSa);

#endif