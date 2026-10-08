"""Hand fixes and runtime patches for hx2go output (exact strings); run in the
generated Go package directory before autofix.py."""
def sub(f, old, new, count=1):
    s = open(f).read()
    assert s.count(old) >= 1, (f, old[:90])
    s = s.replace(old, new, count) if count else s.replace(old, new)
    open(f, 'w').write(s)

# core.Texpr and core.TExpr both lower-case to core_texpr: drop Texpr's
# (static-only) class scaffolding, which only feeds reflection.
s = open('Hx_core_Texpr.go').read()
a = s.index('func Hx_ClassInit_Hx_Obj_VTable_core_texpr()'); b = s.index('func Hx_Field_core_texpr_iter(')
open('Hx_core_Texpr.go', 'w').write(s[:a] + s[b:])

# Array.join on a typed array
sub('Hx_codegen_Genxml.go', '_g.join(":")', 'Hx_Array_Join(_g, ":")')
# super.method inside a generated closure
sub('Hx_context_Common.go', 'super.VTable.Hx_Field_add', 'this.Hx_Obj_context_hashtbllookup.Hx_Field_add')
sub('Hx_context_Common.go', 'super.VTable.Hx_Field_remove', 'this.Hx_Obj_context_hashtbllookup.Hx_Field_remove')
# optional Bool argument of a function-typed variable: callers pass a plain bool
sub('Hx_context_Typecore.go',
    'return func(ctx *Hx_Obj_context_typer, e *Hx_Obj_core_texpr, el HxArray[*Hx_Obj_core_texpr], t Hx_Enum_core_t, p *Hx_Obj_core_pos, forceInline struct { Value bool; Valid bool }) *Hx_Obj_core_texpr{',
    'return func(ctx *Hx_Obj_context_typer, e *Hx_Obj_core_texpr, el HxArray[*Hx_Obj_core_texpr], t Hx_Enum_core_t, p *Hx_Obj_core_pos, forceInline_ bool) *Hx_Obj_core_texpr{ forceInline := struct { Value bool; Valid bool }{forceInline_, true}; _ = forceInline')
# key-value loop over a StringMap typedef (TypeMap)
sub('Hx_core_TFunctions.go',
    'var _hx_reserved_map *Hx_Obj_haxe_imap; _ = _hx_reserved_map\n                     _hx_reserved_map = ((*Hx_Obj_haxe_imap)(a.Hx_Field_aFields))\n                     var _g_map *Hx_Obj_haxe_imap; _ = _g_map',
    'var _hx_reserved_map *Hx_Obj_haxe_ds_stringmap; _ = _hx_reserved_map\n                     _hx_reserved_map = a.Hx_Field_aFields\n                     var _g_map *Hx_Obj_haxe_ds_stringmap; _ = _g_map')
# single-element array literal passed as Array<Dynamic>
sub('Hx_syntax_Reification.go', 'HxMakeArray[*Hx_Obj_core_typehint]( t.Hx_Field_tpConstraints )', 'HxMakeArray[*Hx_Obj_core_typehint]( t.Hx_Field_tpConstraints ).Dyn()')
# Array.concat on a dynamic array
sub('Hx_typing_matcher_Compile.go', 'HxMakeArray[any]( a.Get(j) ).Dyn().concat(acc)', 'Hx_Array_Concat[any](HxMakeArray[any]( a.Get(j) ).Dyn(), acc)')

# Map values stored as concrete maps (StringMap, IntMap...) and read back as
# the Map abstract (*Hx_Obj_haxe_imap): wrap them on demand.
import re, glob
open('hxfix.go', 'w').write('''package main

func hxToImap(v any) *Hx_Obj_haxe_imap {
	switch m := v.(type) {
	case *Hx_Obj_haxe_imap:
		return m
	case Hx_Obj_VTable_haxe_imap:
		return &Hx_Obj_haxe_imap{VTable: m}
	}
	return v.(*Hx_Obj_haxe_imap)
}
''')
for f in glob.glob('*.go'):
    s = open(f).read()
    t = re.sub(r'\b(\w+)\.\((?:\*Hx_Obj_haxe_imap|Hx_Typedef_map|Hx_Typedef_imap)\)', r'hxToImap(\1)', s)
    if t != s: open(f, 'w').write(t)

# HXGO_TRACE=1: print the Go stack when a Go runtime error becomes a Haxe exception
open('hxtrace.go', 'w').write('''package main

import (
	"os"
	"runtime/debug"
)

var hxTrace = os.Getenv("HXGO_TRACE") != ""

func hxTraceGoError(e any) {
	if hxTrace {
		if err, ok := e.(error); ok {
			os.Stderr.WriteString("HXGO_TRACE " + err.Error() + "\\n" + string(debug.Stack()))
		}
	}
}
''')
sub('Hx_haxe_Exception.go', '     goError, isGoError = e.(error)\n', '     goError, isGoError = e.(error)\n     hxTraceGoError(e)\n')

# HXGO_TRACE: also log every thrown Haxe value except control-flow singletons
s = open('hxtrace.go').read()
s = s.replace('import (\n', 'import (\n\t"fmt"\n')
s += '''
func hxTraceThrow(v any) {
	if !hxTrace {
		return
	}
	t := fmt.Sprintf("%T", v)
	switch t {
	case "*main.Hx_Obj_core_ds_notfound", "*main.Hx_Obj_core_ds_streamfailure", "*main.Hx_Obj_core_ds_exit":
		return
	}
	os.Stderr.WriteString("HXGO_THROW " + t + " " + fmt.Sprint(v) + "\\n" + string(debug.Stack()) + "\\n")
}
'''
open('hxtrace.go', 'w').write(s)
sub('Hx_haxe_Exception.go', 'func Hx_Field_haxe_exception_thrown(value any) *Hx_Obj_haxe_exception {\n', 'func Hx_Field_haxe_exception_thrown(value any) *Hx_Obj_haxe_exception {\n     hxTraceThrow(value)\n')

# Std.string has no recursion limit; typed ASTs and types are cyclic (a thrown
# unification error is stringified by ValueException). Cap the depth like
# other targets do.
sub('Hx_Std.go', 'func Hx_Field_std_string(s any) string {\n',
    'var hxStrDepth int\nfunc Hx_Field_std_string(s any) string {\n     if hxStrDepth >= 5 { return "<...>" }\n     hxStrDepth++; defer func() { hxStrDepth-- }()\n')

# dynamic closure adapter: a Void function used where a value-returning
# function type is expected returns no results
sub('Hx_go_haxe_HxDynamic.go',
    '                 _hx_tmp_5 = results[i]\n                 var v reflect.Value; _ = v\n                 v = Hx_Field_go_haxe_hxdynamic_convertToType(_hx_tmp_5, t.Out(int(i)))',
    '                 var v reflect.Value; _ = v\n                 if int(i) >= len(results) { v = reflect.Zero(t.Out(int(i))) } else {\n                 _hx_tmp_5 = results[i]\n                 v = Hx_Field_go_haxe_hxdynamic_convertToType(_hx_tmp_5, t.Out(int(i)))\n                 }')

# catch (e:Dynamic) of a haxe.Exception subclass: unwrap() runs on the embedded
# base struct and returns *Hx_Obj_haxe_exception, losing the subclass; the
# most-derived object is the VTable.
sub('Hx_haxe_Exception.go',
    '                 r = Hx_Field_go_haxe_hxdynamic_call(_hx_tmp_0, HxMakeArray[any]().Dyn())\n',
    '                 r = Hx_Field_go_haxe_hxdynamic_call(_hx_tmp_0, HxMakeArray[any]().Dyn())\n                 if be, ok := r.(*Hx_Obj_haxe_exception); ok && be != nil && be.VTable != nil { r = any(be.VTable) }\n')

# catch clauses on a typedef alias of an exception class (e.g. NotFound via a
# typedef) pass the alias name to catchValue, which resolves classes by name:
# use the aliased type
aliases = {}
for f in glob.glob('*.go'):
    for m in re.finditer(r'^type (Hx_Typedef_\w+) = (\*?Hx_Obj_\w+)$', open(f).read(), re.M):
        aliases[m.group(1)] = m.group(2)
for f in glob.glob('*.go'):
    s = open(f).read()
    t = re.sub(r'catchValue\(_hx_ex, "(Hx_Typedef_\w+)"\)', lambda m: 'catchValue(_hx_ex, "%s")' % aliases.get(m.group(1), m.group(1)), s)
    if t != s: open(f, 'w').write(t)

# Strings: hx2go's String functions count runes from the start on every call
# (charCodeAt is O(n), so lexing is quadratic), and indexOf returns a byte
# offset while substr/charCodeAt use rune indices. Wrap them: O(1) paths for
# ASCII strings (cached per string data pointer), rune-correct indexOf and
# lastIndexOf, and a cached rune count for String.length.
s = open('Hx_go_haxe_HxString.go').read()
for name in ['charAt', 'charCodeAt', 'indexOf', 'lastIndexOf', 'substr', 'substring']:
    s = s.replace('func Hx_Field_go_haxe_hxstring_%s(' % name, 'func hxOrig_%s(' % name, 1)
open('Hx_go_haxe_HxString.go', 'w').write(s)
open('hxstr.go', 'w').write('''package main

import (
	"strings"
	"unicode/utf8"
	"unsafe"
)

type hxStrInfo struct {
	p     *byte
	n     int
	ascii bool
	runes int
	arr   []rune // non-ASCII strings: code points, filled on first indexed access
}

var hxStrCache [4]hxStrInfo
var hxStrNext int

func hxInfo(s string) *hxStrInfo {
	p := unsafe.StringData(s)
	for i := range hxStrCache {
		c := &hxStrCache[i]
		if c.p == p && c.n == len(s) {
			return c
		}
	}
	ascii := true
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			ascii = false
			break
		}
	}
	runes := len(s)
	if !ascii {
		runes = utf8.RuneCountInString(s)
	}
	c := &hxStrCache[hxStrNext]
	hxStrNext = (hxStrNext + 1) % len(hxStrCache)
	*c = hxStrInfo{p, len(s), ascii, runes, nil}
	return c
}

func hxIsASCII(s string) bool {
	if len(s) < 64 {
		for i := 0; i < len(s); i++ {
			if s[i] >= 0x80 {
				return false
			}
		}
		return true
	}
	return hxInfo(s).ascii
}

func hxRuneCount(s string) int {
	if len(s) < 64 {
		return utf8.RuneCountInString(s)
	}
	return hxInfo(s).runes
}

// byte offset of rune index r (r <= rune count)
func hxByteOffset(s string, r int) int {
	if hxIsASCII(s) {
		return r
	}
	b := 0
	for i := 0; i < r && b < len(s); i++ {
		_, size := utf8.DecodeRuneInString(s[b:])
		b += size
	}
	return b
}

func Hx_Field_go_haxe_hxstring_charCodeAt(s string, index int32) struct { Value int32; Valid bool } {
	if hxIsASCII(s) {
		if index < 0 || int(index) >= len(s) {
			return struct { Value int32; Valid bool }{}
		}
		return struct { Value int32; Valid bool }{int32(s[index]), true}
	}
	if len(s) >= 64 {
		c := hxInfo(s)
		if c.arr == nil {
			c.arr = []rune(s)
		}
		if index < 0 || int(index) >= len(c.arr) {
			return struct { Value int32; Valid bool }{}
		}
		return struct { Value int32; Valid bool }{int32(c.arr[index]), true}
	}
	return hxOrig_charCodeAt(s, index)
}

func Hx_Field_go_haxe_hxstring_charAt(s string, index int32) string {
	if hxIsASCII(s) {
		if index < 0 || int(index) >= len(s) {
			return ""
		}
		return s[index : index+1]
	}
	return hxOrig_charAt(s, index)
}

func Hx_Field_go_haxe_hxstring_substr(s string, pos int32, l struct { Value int32; Valid bool }) string {
	if hxIsASCII(s) && pos >= 0 && (!l.Valid || l.Value >= 0) {
		n := int32(len(s))
		if pos > n {
			return ""
		}
		end := n
		if l.Valid && pos+l.Value < n {
			end = pos + l.Value
		}
		return s[pos:end]
	}
	return hxOrig_substr(s, pos, l)
}

func Hx_Field_go_haxe_hxstring_substring(s string, start int32, endIndex struct { Value int32; Valid bool }) string {
	if hxIsASCII(s) {
		n := int32(len(s))
		end := n
		if endIndex.Valid {
			end = endIndex.Value
		}
		if start < 0 {
			start = 0
		}
		if end < 0 {
			end = 0
		}
		if start > end {
			start, end = end, start
		}
		if start > n {
			start = n
		}
		if end > n {
			end = n
		}
		return s[start:end]
	}
	return hxOrig_substring(s, start, endIndex)
}

func Hx_Field_go_haxe_hxstring_indexOf(s string, str string, startIndex struct { Value int32; Valid bool }) int32 {
	start := 0
	if startIndex.Valid && startIndex.Value > 0 {
		start = int(startIndex.Value)
	}
	n := hxRuneCount(s)
	if start > n {
		if str == "" {
			return int32(n)
		}
		return -1
	}
	b := hxByteOffset(s, start)
	f := strings.Index(s[b:], str)
	if f < 0 {
		return -1
	}
	if hxIsASCII(s) {
		return int32(start + f)
	}
	return int32(start + utf8.RuneCountInString(s[b:b+f]))
}

func Hx_Field_go_haxe_hxstring_lastIndexOf(s string, str string, startIndex struct { Value int32; Valid bool }) int32 {
	n := hxRuneCount(s)
	start := n
	if startIndex.Valid && startIndex.Value >= 0 && int(startIndex.Value) < n {
		start = int(startIndex.Value)
	}
	// a match may begin at rune index <= start
	limit := hxByteOffset(s, start) + len(str)
	if limit > len(s) {
		limit = len(s)
	}
	f := strings.LastIndex(s[:limit], str)
	if f < 0 {
		return -1
	}
	if hxIsASCII(s) {
		return int32(f)
	}
	return int32(utf8.RuneCountInString(s[:f]))
}
''')
for f in glob.glob('*.go'):
    if f in ('hxstr.go',): continue
    s = open(f).read()
    if 'utf8.RuneCountInString(' not in s: continue
    t = s.replace('utf8.RuneCountInString(', 'hxRuneCount(')
    if 'utf8.' not in t:
        t += '\nvar _ = utf8.RuneError\n'
    open(f, 'w').write(t)

# HXGO_CPUPROFILE=file: CPU profile through hx2go's (empty) profiling hooks
sub('Hx_go_haxe_HxProfile.go', 'func Hx_Field_go_haxe_hxprofile_start() {\n}', 'func Hx_Field_go_haxe_hxprofile_start() {\n    if p := os.Getenv("HXGO_CPUPROFILE"); p != "" { if f, err := os.Create(p); err == nil { pprof.StartCPUProfile(f) } }\n}')
sub('Hx_go_haxe_HxProfile.go', 'func Hx_Field_go_haxe_hxprofile_stop() {\n}', 'func Hx_Field_go_haxe_hxprofile_stop() {\n    pprof.StopCPUProfile()\n}')
s = open('Hx_Sys.go').read()
s = s.replace('func Hx_Field_sys_exit(code int32) {\n', 'func Hx_Field_sys_exit(code int32) {\n     Hx_Field_go_haxe_hxprofile_stop()\n', 1)
open('Hx_Sys.go', 'w').write(s)

# Mutex ownership asks for the goroutine id by formatting a stack trace
# (runtime.Stack) on every acquire/release. While the program has a single
# goroutine (no worker threads, e.g. -D disable-parallelism) its id is fixed.
s = open('Hx_sys_thread_ThreadImpl.go').read()
m = re.search(r'func Hx_Field_sys_thread__threadimpl_threadimpl_impl__getGoroutineId\([^)]*\) (\w+) \{\n', s)
s = s[:m.end()] + '     if runtime.NumGoroutine() == 1 { return 1 }\n' + s[m.end():]
open('Hx_sys_thread_ThreadImpl.go', 'w').write(s)
