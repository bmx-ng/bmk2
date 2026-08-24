#ifndef BMK_IMPORTED_PRAGMA_ACTIVE
#error quoted Import did not inherit its lexical bmk cc_opts
#endif

#ifdef BMK_REMOVED_PRAGMA_MUST_NOT_REACH_IMPORT
#error a removed lexical bmk option was inherited
#endif

#if defined(_WIN32) && !defined(BMK_IMPORTED_PRAGMA_WIN32)
#error active Win32 bmk pragma option was not inherited
#endif

#if !defined(_WIN32) && !defined(BMK_IMPORTED_PRAGMA_NOT_WIN32)
#error active non-Win32 bmk pragma option was not inherited
#endif

int bmk_imported_pragma_value(void) {
    return 42;
}
