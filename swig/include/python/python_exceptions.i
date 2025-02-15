/*
 * This was the cpl_exceptions.i code.  But since python is the only one
 * different (should support old method as well as new one)
 * it was moved into this file.
 */
%{
static int bUseExceptions=0;
static CPLErrorHandler pfnPreviousHandler = CPLDefaultErrorHandler;

static void CPL_STDCALL
PythonBindingErrorHandler(CPLErr eclass, int code, const char *msg )
{
  /*
  ** Generally we want to suppress error reporting if we have exceptions
  ** enabled as the error message will be in the exception thrown in
  ** Python.
  */

  /* If the error class is CE_Fatal, we want to have a message issued
     because the CPL support code does an abort() before any exception
     can be generated */
  if (eclass == CE_Fatal ) {
    pfnPreviousHandler(eclass, code, msg );
  }

  /*
  ** We do not want to interfere with non-failure messages since
  ** they won't be translated into exceptions.
  */
  else if (eclass != CE_Failure ) {
    pfnPreviousHandler(eclass, code, msg );
  }
  else {
    CPLSetThreadLocalConfigOption("__last_error_message", msg);
    CPLSetThreadLocalConfigOption("__last_error_code", CPLSPrintf("%d", code));
  }
}
%}

%exception GetUseExceptions
{
%#ifdef SED_HACKS
    if( bUseExceptions ) bLocalUseExceptionsCode = FALSE;
%#endif
    result = GetUseExceptions();
}

%inline %{

static
int GetUseExceptions() {
  return bUseExceptions;
}

static
void UseExceptions() {
  CPLErrorReset();
  if( !bUseExceptions )
  {
    bUseExceptions = 1;
    char* pszNewValue = CPLStrdup(CPLSPrintf("%s %s",
                   MODULE_NAME,
                   CPLGetConfigOption("__chain_python_error_handlers", "")));
    CPLSetConfigOption("__chain_python_error_handlers", pszNewValue);
    CPLFree(pszNewValue);
    // if the previous logger was custom, we need the user data available
    pfnPreviousHandler =
        CPLSetErrorHandlerEx( (CPLErrorHandler) PythonBindingErrorHandler, CPLGetErrorHandlerUserData() );
  }
}

static
void DontUseExceptions() {
  CPLErrorReset();
  if( bUseExceptions )
  {
    const char* pszValue = CPLGetConfigOption("__chain_python_error_handlers", "");
    if( strncmp(pszValue, MODULE_NAME, strlen(MODULE_NAME)) != 0 ||
        pszValue[strlen(MODULE_NAME)] != ' ')
    {
        CPLError(CE_Failure, CPLE_NotSupported,
                 "Cannot call %s.DontUseExceptions() at that point since the "
                 "stack of error handlers is: %s", MODULE_NAME, pszValue);
        return;
    }
    char* pszNewValue = CPLStrdup(pszValue + strlen(MODULE_NAME) + 1);
    if( pszNewValue[0] == ' ' && pszNewValue[1] == '\0' )
    {
        CPLFree(pszNewValue);
        pszNewValue = NULL;
    }
    CPLSetConfigOption("__chain_python_error_handlers", pszNewValue);
    CPLFree(pszNewValue);
    bUseExceptions = 0;
    // if the previous logger was custom, we need the user data available. Preserve it.
    CPLSetErrorHandlerEx( pfnPreviousHandler, CPLGetErrorHandlerUserData());
  }
}
%}

%{
/* Completely unrelated: just to avoid Coverity warnings */

static int bReturnSame = 1;

void NeverCallMePlease() {
    bReturnSame = 0;
}

/* Some SWIG code generates dead code, which Coverity warns about */
template<class T> static T ReturnSame(T x)
{
    if( bReturnSame )
        return x;
    return 0;
}

static void ClearErrorState()
{
    CPLSetThreadLocalConfigOption("__last_error_message", NULL);
    CPLSetThreadLocalConfigOption("__last_error_code", NULL);
    CPLErrorReset();
}

static void StoreLastException() CPL_UNUSED;

// Note: this is also copy&pasted in gdal_array.i
static void StoreLastException()
{
    const char* pszLastErrorMessage =
        CPLGetThreadLocalConfigOption("__last_error_message", NULL);
    const char* pszLastErrorCode =
        CPLGetThreadLocalConfigOption("__last_error_code", NULL);
    if( pszLastErrorMessage != NULL && pszLastErrorCode != NULL )
    {
        CPLErrorSetState( CE_Failure,
            static_cast<CPLErrorNum>(atoi(pszLastErrorCode)),
            pszLastErrorMessage);
    }
}

%}

%include exception.i

%exception {

    if ( bUseExceptions ) {
        ClearErrorState();
    }
    $action
%#ifndef SED_HACKS
    if ( bUseExceptions ) {
      CPLErr eclass = CPLGetLastErrorType();
      if ( eclass == CE_Failure || eclass == CE_Fatal ) {
        SWIG_exception( SWIG_RuntimeError, CPLGetLastErrorMsg() );
      }
    }
%#endif
}

%feature("except") Open {
    if ( bUseExceptions ) {
        ClearErrorState();
    }
    $action
%#ifndef SED_HACKS
    if( result == NULL && bUseExceptions ) {
      CPLErr eclass = CPLGetLastErrorType();
      if ( eclass == CE_Failure || eclass == CE_Fatal ) {
        SWIG_exception( SWIG_RuntimeError, CPLGetLastErrorMsg() );
      }
    }
%#endif
    if( result != NULL && bUseExceptions ) {
        StoreLastException();
%#ifdef SED_HACKS
        bLocalUseExceptionsCode = FALSE;
%#endif
    }
}

%feature("except") OpenShared {
    if ( bUseExceptions ) {
        ClearErrorState();
    }
    $action
%#ifndef SED_HACKS
    if( result == NULL && bUseExceptions ) {
      CPLErr eclass = CPLGetLastErrorType();
      if ( eclass == CE_Failure || eclass == CE_Fatal ) {
        SWIG_exception( SWIG_RuntimeError, CPLGetLastErrorMsg() );
      }
    }
%#endif
    if( result != NULL && bUseExceptions ) {
        StoreLastException();
%#ifdef SED_HACKS
        bLocalUseExceptionsCode = FALSE;
%#endif
    }
}

%feature("except") OpenEx {
    if ( bUseExceptions ) {
        ClearErrorState();
    }
    $action
%#ifndef SED_HACKS
    if( result == NULL && bUseExceptions ) {
      CPLErr eclass = CPLGetLastErrorType();
      if ( eclass == CE_Failure || eclass == CE_Fatal ) {
        SWIG_exception( SWIG_RuntimeError, CPLGetLastErrorMsg() );
      }
    }
%#endif
    if( result != NULL && bUseExceptions ) {
        StoreLastException();
%#ifdef SED_HACKS
        bLocalUseExceptionsCode = FALSE;
%#endif
    }
}

%pythoncode %{
  class ExceptionMgr(object):
      """
      Context manager to manage Python Exception state
      for GDAL/OGR/OSR/GNM.

      Separate exception state is maintained for each
      module (gdal, ogr, etc), and this class appears independently
      in all of them. This is built in top of calls to the older
      UseExceptions()/DontUseExceptions() functions.

      Example::

          >>> print(gdal.GetUseExceptions())
          0
          >>> with gdal.ExceptionMgr(useExceptions=True):
          ...     # Exceptions are now in use
          ...     print(gdal.GetUseExceptions())
          1
          >>>
          >>> # Exception state has now been restored
          >>> print(gdal.GetUseExceptions())
          0

      """
      def __init__(self, useExceptions):
          """
          Save whether or not this context will be using exceptions
          """
          self.requestedUseExceptions = useExceptions

      def __enter__(self):
          """
          On context entry, save the current GDAL exception state, and
          set it to the state requested for the context

          """
          self.currentUseExceptions = (GetUseExceptions() != 0)

          if self.requestedUseExceptions:
              UseExceptions()
          else:
              DontUseExceptions()

      def __exit__(self, exc_type, exc_val, exc_tb):
          """
          On exit, restore the GDAL/OGR/OSR/GNM exception state which was
          current on entry to the context
          """
          if self.currentUseExceptions:
              UseExceptions()
          else:
              DontUseExceptions()
%}
