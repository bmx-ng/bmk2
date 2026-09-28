#if CONFIG_VALUE != 2
#error Module native option not applied
#endif
int NativeConfig(void) { return 20 + CONFIG_VALUE; }
