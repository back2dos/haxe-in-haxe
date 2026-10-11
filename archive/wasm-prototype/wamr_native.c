// EXPERIMENTAL: host functions of backend/ modules for WAMR's iwasm --native-lib.
#include <stdio.h>
#include "wasm_export.h"

static void printInt_wrapper(wasm_exec_env_t env, int v) { printf("%d\n", v); }

static NativeSymbol symbols[] = {{"printInt", printInt_wrapper, "(i)", NULL}};

uint32_t get_native_lib(char **module_name, NativeSymbol **native_symbols) {
	*module_name = "env";
	*native_symbols = symbols;
	return sizeof(symbols) / sizeof(NativeSymbol);
}
