#ifdef CONFIG_VALUE
#error Module options leaked into a sibling
#endif
int SiblingValue(void) { return 7; }
