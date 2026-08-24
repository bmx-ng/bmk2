#ifdef BMK_IMPORTED_PRAGMA_ACTIVE
#error popped bmk cc_opts leaked into an import after the lexical scope
#endif

int bmk_imported_pragma_sibling(void) {
    return 0;
}
