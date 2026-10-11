# Translation and compilation status

Snapshot: 2026-09-04. Pinned upstream source:
`b10fa6e93c0206cc0dc8f7abba98534e3edac248`.

## Current coverage (2026-10-09)

Every upstream `.ml` file under `haxe/src/` is listed below, with its Haxe
counterpart or the reason it has none. Ported and tested against the
reference (results in `test/TESTING.md`):

- the batch compiler: syntax, typing, finalization, filters, optimizer,
  analyzer, DCE, coroutines and the HXB writer (`haxe.Main`);
- the macro runtime: `macro/eval/*.ml`, `macroApi.ml` and `macroContext.ml`,
  including `evalSsl.ml` (mbedtls), `evalLuv.ml` (libuv, with `eval.luv`
  threads, thread pool and synchronization) and `evalThread.ml`. The
  natives that call mbedtls/libuv need the hxc host (`hxc.NativeSsl`,
  `hxc.NativeUv`); on HashLink they fail explicitly, except the `eval.luv`
  threads and primitives, which need no libuv;
- HXB library input: `hxbReader.ml`, `hxbReaderApi.ml`, `hxbLib.ml`;
- the compilation server and its caches: `compiler/server/*.ml`,
  `compilationCache.ml`, `context/commonCache.ml`, `pipeThings.ml`,
  `tasks.ml`; the server's HXB module cache uses the HXB reader;
- haxelib (`add_libs` in `highLevel.ml`);
- display services: `typerDisplay.ml`, `context/display/*`,
  `displayOutput.ml`, `displayProcessing.ml`, `completionItem.ml`,
  `genjson.ml`, `jsonRpc.ml`, `jsonrpc_handler.ml`.

Status 2026-10-11: the Eval debugger (`evalDebug*.ml`, `-D
eval-debugger=host:port`), `jsonRpcSocket.ml`, `server/module`
(`Genjson.generate_module` and `hxb_reader_api_com` over the HXB module cache)
and `server/memory` are translated. Object sizes (OCaml's `Objsize`) are what
the host measures: the hxc build walks its own heap (`hxc_NativeGc_objsize`),
other hosts report 0 (see `src/context/Memory.hx`).

Not ported: the HL bytecode interpreter. Every target generator
is translated (see "Target generator coverage"). `EvalLock.hx` (OCaml's
runtime lock for Eval threads) has no upstream module.

## History

Status 2026-10-07: the first milestone is reached. The translated batch
compiler (`haxe.Main`) emits HXB byte-identical to the pinned reference for
all 275 accepted conformance cases, and rejects the 7 cases the reference
rejects; see `test/TESTING.md`. Since the snapshot below, `hxbWriter.ml`,
`grammar.ml` and `lexer.ml` were retranslated directly
(`src/compiler/hxb/HxbWriter.hx`, `src/syntax/Grammar.hx`,
`src/syntax/Lexer.hx`), and the batch entry in `haxe.ml` became
`src/haxe/Main.hx`. The earlier hand-written versions remain as
`LegacyGrammar`, `LegacyLexer` and `LegacyMain`, used only by the bootstrap
unit tests.

Status 2026-10-08: macro execution works. `macro/eval/*.ml` and `macroApi.ml`
are translated in `src/macros/` and `typing/macroContext.ml` in
`src/typing/MacroContext.hx`. All 66 macro-context conformance cases are
byte-identical. The debugger (`evalDebug*.ml`), libuv (`evalLuv.ml`) and mbedtls
(`evalSsl.ml`, except its enum constants) were not ported at first; libuv and
mbedtls followed on 2026-10-09 (below).

Status 2026-10-09: HXB library input (`--hxb-lib`) works. `hxbReader.ml`,
`hxbReaderApi.ml` and `hxbLib.ml` are translated in `src/compiler/hxb/`,
`typeloadCacheHook.ml` in `src/typing/TypeloadCacheHook.hx`, the HXB branch of
`nativeLibraryHandler.ml` in `src/context/NativeLibraryHandler.hx`, and the
`hxb_reader_api_typeload` class and `load_hxb_module` of `typeloadModule.ml` in
`src/typing/TypeloadModule.hx`. The ZIP reading that `hxbLib.ml` takes from
`libs/ziplib` is reproduced in `src/core/ZipInput.hx`. Of `commonCache.ml`,
only the server cache uses the reader (`HxbReader.dump_stats` in
`cache_context`), so nothing of it is needed by the batch `--hxb-lib` path.
See `test/TESTING.md`.

Status 2026-10-09: the compilation server, its caches and haxelib integration
are translated: `compiler/server/*.ml` in `src/compiler/server/`,
`compilationCache.ml`, `pipeThings.ml` and `tasks.ml` in `src/compiler/`,
`context/commonCache.ml` and `typing/typeloadCacheHook.ml`, the client and
server entry of `haxe.ml` (`--connect`, `--wait`, `--server-connect`) in
`src/haxe/Main.hx`, and `add_libs` (`-L`/`--library`, which runs `haxelib
path`) with the `Expand` markers of `args.ml` in `src/compiler/HighLevel.hx`.
As upstream, the batch compiler also runs through `Server.setup_server_context`
and the cache hooks. The server's HXB module cache restores modules with the
translated HXB reader (`HxbReaderApiServer` implements `HxbReaderApi`), and
`-D disable-hxb-cache` keeps typed modules in memory instead. The pinned upstream no longer implements `--wait stdio` (it reports "Invalid
host/port"); the port behaves the same. The host socket API is IPv4 only. See
`test/TESTING.md` for the server and haxelib results.

Status 2026-10-09: display services work in batch mode. `--display` takes a
JSON-RPC request like the pinned reference (the legacy `file@pos` form is a
JSON-RPC parse error upstream too). `typerDisplay.ml`, `context/display/*`,
`displayOutput.ml`, `displayProcessing.ml`, `completionItem.ml`, `genjson.ml`,
`jsonRpc.ml`, `jsonrpc_handler.ml`, are translated, and every display hook in the typer calls them directly
(`context/DeferredServices.hx` is gone). OCaml `Hashtbl` iteration order,
which display output exposes, is reproduced by `core.ds.OcamlHash`
(`caml_hash`) with `core.ds.OcamlHashtbl`. Results of the display corpus are
in `test/TESTING.md`.

Status 2026-10-09: `evalSsl.ml` and `evalLuv.ml` are translated
(`src/macros/eval/EvalSsl.hx`, `EvalLuv.hx`) over the hxc runtime's mbedtls
and libuv natives (`hxc/rt/rt_ssl.c`, `rt_uv.c`), including `eval.luv`
`Thread`, `ThreadPool`, `Once`, `Mutex`, `RwLock`, `Semaphore`, `Condition`
and `Barrier` on host threads. Eval's `sys.io.Process` follows
`libs/extc/process.ml` (`EvalProcess.hx`). `EvalLock.hx` serializes Eval
threads as OCaml's runtime lock does (a documented deviation: the port's
host threads run in parallel). The upstream test suite's threads step passes
144/144 on the hxc build.

Status 2026-10-11: the legacy bootstrap path (the hand-written loader and typer
`TypeloadModule`/`TypeloadParse`, `LegacyGrammar`, `LegacyLexer`,
`Preprocessor` and `LegacyMain`) moved to `archive/legacy-bootstrap/`. The
translations of `typeloadModule.ml` and `typeloadParse.ml` took their natural
names (`src/typing/TypeloadModule.hx`, `TypeloadParse.hx`, formerly
`ModuleTyping.hx` and `SourceParser.hx`), and the unit tests run the translated
pipeline. The `core/` counterparts that predated the translation snapshot were
audited line by line against upstream (see the table).

## Translation snapshot

**The pending counterpart batch was completed in `2fcd217`.** This inventory records file coverage,
not compilation or behavioral correctness. No builds or tests were run for the translation-first
batches. The bootstrap entry point still uses its existing loader; the new
compiler pipeline is included separately by `test/compile-all.hxml`.

- 126 new draft/support Haxe files across the translation-first batches.
- 124 upstream ML files have new draft counterparts.
- 33 upstream ML files have pre-existing counterparts; completeness is unaudited (the 21 `core/` ones were audited on 2026-10-11).
- 0 additional candidate ML files have no corresponding HX file yet.

This follow-up added 59 in-scope counterparts from the previous 69 pending
candidates. The other ten are explicitly deferred below. `HighLevel` now also
implements haxelib `add_libs` (2026-10-09).

The candidate list is deliberately conservative, not a proven minimal dependency
closure. Translate the source-only HXB path, including its shared filtering and
typing helpers; exclude unrelated service/runtime implementations. Shared types
and batch-used helpers inside otherwise deferred areas still need extraction
when required. An existing counterpart may combine several upstream modules or
implement only a subset: file presence does not close that work.

## Compilation work

The compile phase reconciles enum/record layouts, callback signatures, persistent
maps, typed exceptions, and Haxe secondary-type imports. New runtime adapters
provide OCaml-style lists/maps/tables, fixed-width integer parsing, streams, and
thread scheduling. `Record.withFields` preserves shallow record updates.
`TaskPool` stands in for Domainslib with host threads (persistent workers on
HL/C and hxc, threads scoped to the call elsewhere) instead of a
work-stealing pool; `CompilerIo` uses byte queues instead of OCaml Unix pipes.

Shared HXB-path helpers were extracted from otherwise deferred areas:

- `context/display/DeprecationCheck.hx`: compiler deprecation warnings.
- `context/display/ImportHandling.hx`: imports, aliases, wildcard imports, using
  resolution, and bookkeeping, including the display branches.
- `core/display/DisplayPosition.hx` and `Javadoc.hx`: shared positions and
  documentation parsing required by typing.
- `codegen/Genxml.hx`: RTTI type serialization before HXB save; the standalone
  XML output backend remains deferred.
- `context/HxbReaderStats.hx`: shared statistics declarations, without HXB input.
- `typing/ModuleTyping.hx` and `SourceParser.hx` (now `TypeloadModule.hx` and
  `TypeloadParse.hx`): source-backed module creation, loading, package
  rules/remapping, import.hx processing, and parser integration required by
  `TyperEntry`; the existing bootstrap loader remained separate (now archived).

At the time, display, server, macro-runtime, native-library and target
dispatch bodies were kept under `archive/deferred/`, outside the build class path.
Display, server and the macro runtime have since been translated in `src/`
(see the history above); `archive/deferred/` now only holds old drafts, and the
remaining unsupported services (the HL interpreter) are
rejected explicitly at their call sites. In-scope typing and filtering paths remain in
the all-module build. Compilation does not establish runtime correctness,
conformance, or completion of the pre-existing HXB writer. The subsequent runtime test phase is tracked in
`test/TESTING.md`.

## Draft conventions and reconciliation

- Each new source translation names its upstream file and is marked unvalidated.
- OCaml tuples/records become Haxe records, lists become arrays, and modules become classes or secondary types.
- Drafts may use different unresolved API/type names, ordered-map adapters, exception representations, and callback conventions. Reconcile these in the later compile phase.
- Some exception catches use `Dynamic`; exception-type alignment, OCaml atomics, identity/projections, and persistent-map operations remain for reconciliation.
- Macro/display/native hooks retained in shared modules do not implement those deferred runtimes.
- Ordered source traversals remain explicit in the translations; pool identity and serialization ordering still require conformance validation later.
- Pre-existing `TypeloadModule`, parser and bootstrap paths are not automatically full one-to-one translations. Audit their source coverage before closing the pass. (The legacy loader, parser and entry point are now archived.)

## Candidate source coverage

| Upstream under `haxe/src/` | Haxe counterpart | Status |
| --- | --- | --- |
| `codegen/codegen.ml` | `src/codegen/Codegen.hx` | Draft translated |
| `codegen/dump.ml` | `src/codegen/Dump.hx` | Draft translated |
| `codegen/fixOverrides.ml` | `src/codegen/FixOverrides.hx` | Draft translated |
| `codegen/overloads.ml` | `src/codegen/Overloads.hx` | Draft translated |
| `compiler/args.ml` | `src/compiler/Args.hx` | Translated (audited). Deviations: `path` values of `SetMain`/`AddClass` are flat lists; `Terminal_size` columns come from `$COLUMNS`; the arg descriptions omit the never-invoked `Arg.t`; `expand_hxml` is a port-only helper of the legacy bootstrap entry |
| `compiler/compiler.ml` | `src/compiler/Compiler.hx` | Draft translated |
| `compiler/generate.ml` | `src/compiler/Generate.hx` | Translated, including `check_auxiliary_output` (`--xml`, `--json`, `-D gen-hx-classes`) |
| `compiler/haxe.ml` | `src/haxe/Main.hx` | Translated, including client/server entry |
| `compiler/helper.ml` | `src/compiler/Helper.hx` | Translated (audited); `ExtString` strip/split and `String.sub` semantics emulated |
| `compiler/highLevel.ml` | `src/compiler/HighLevel.hx` | Translated, including haxelib `add_libs` |
| `compiler/hxb/hxbData.ml` | `src/compiler/hxb/HxbData.hx` | Translated (audited) |
| `compiler/hxb/hxbLib.ml` | `src/compiler/hxb/HxbLib.hx` | Translated; ZIP reading in `src/core/ZipInput.hx` (from `libs/ziplib/zip.ml`) |
| `compiler/hxb/hxbReader.ml` | `src/compiler/hxb/HxbReader.hx` | Translated; `hxb_reader_stats` stays in `src/context/HxbReaderStats.hx` |
| `compiler/hxb/hxbReaderApi.ml` | `src/compiler/hxb/HxbReaderApi.hx` | Translated (virtual class as interface) |
| `compiler/hxb/hxbWriter.ml` | `src/compiler/hxb/HxbWriter.hx` | Translated (audited). Deviations: effects (`UnboundTTP`) as a handler stack; growable buffer for `SimnBuffer`; texpr type pool keyed by content hash; `write_dynarray` is `writeList` |
| `compiler/hxb/hxbWriterConfig.ml` | `src/compiler/hxb/HxbWriterConfig.hx` | Translated (audited); the reader/writer functors take a `DataReaderApi`/`DataWriterApi` (Json here, Eval in `MacroContext`); JSON parsed with `haxe.Json` |
| `compiler/io/compilerIo.ml` | `src/compiler/io/CompilerIo.hx` | Draft translated |
| `compiler/io/compilerMessage.ml` | `src/compiler/io/CompilerMessage.hx` | Draft translated |
| `compiler/io/compilerOutput.ml` | `src/compiler/io/CompilerOutput.hx` | Draft translated |
| `compiler/messageReporting.ml` | `src/compiler/MessageReporting.hx` | Draft translated |
| `compiler/parsedArg.ml` | `src/compiler/ParsedArg.hx` | Translated (audited); `path` arguments are flat lists |
| `context/abstractCast.ml` | `src/context/AbstractCast.hx` | Draft translated |
| `context/common.ml` | `src/context/Common.hx` | Draft translated |
| `context/coreApiConfig.ml` | `src/context/CoreApiConfig.hx` | Draft translated |
| `context/dotGraph.ml` | `src/context/DotGraph.hx` | Draft translated |
| `context/dumpConfig.ml` | `src/context/DumpConfig.hx` | Draft translated |
| `context/formatString.ml` | `src/context/FormatString.hx` | Draft translated |
| `context/lookup.ml` | `src/context/Lookup.hx` | Draft translated |
| `context/nativeLibraryHandler.ml` | `src/context/NativeLibraryHandler.hx` | HXB, JVM (`JavaModern`) and SWF (`SwfLoader`) branches |
| `context/nativeLibraries.ml` | `src/context/NativeLibraries.hx` | Draft translated |
| `context/parallel.ml` | `src/context/Parallel.hx` | Draft translated |
| `context/platformConfig.ml` | `src/context/PlatformConfig.hx` | Draft translated |
| `context/purityState.ml` | `src/context/PurityState.hx` | Draft translated |
| `context/resolution.ml` | `src/context/Resolution.hx` | Draft translated |
| `context/safeCom.ml` | `src/context/SafeCom.hx` | Draft translated |
| `context/typecore.ml` | `src/context/Typecore.hx` | Draft translated |
| `context/typerPass.ml` | `src/context/TyperPass.hx` | Draft translated |
| `core/abstract.ml` | `src/core/Abstract.hx` | Draft translated |
| `core/ast.ml` | `src/core/Ast.hx` | Translated (audited); module Printer in `AstPrinter.hx`, `map_expr` in `AstExprMapper.hx`, `unescape` in `syntax/Lexer.hx`, module Expr in the class `Ast`; `getValueMeta` returns a StringMap (only looked up) |
| `core/classPath.ml` | `src/core/ClassPath.hx` | Translated (audited); the virtual class is the interface `IClassPath` |
| `core/classPaths.ml` | `src/core/ClassPaths.hx` | Translated (audited); the lookup cache is a Map (never iterated) |
| `core/data/dataReaderApi.ml` | `src/core/data/DataReaderApi.hx` | Draft translated |
| `core/data/dataWriterApi.ml` | `src/core/data/DataWriterApi.hx` | Draft translated |
| `core/data/jsonDataApi.ml` | `src/core/data/JsonDataApi.hx` | Translated (audited); reads `core.Json` values |
| `core/data/metaDataApi.ml` | `src/core/data/MetaDataApi.hx` | Draft translated |
| `core/define.ml` | `src/core/Define.hx` | Translated (audited); DefineList is `DefineRegistry.hx`, a define is its key string (so `Custom k` and a built-in define `k` are not distinguished), signatures are hex MD5 |
| `core/displayTypes.ml` | `src/core/DisplayTypes.hx` | Draft translated |
| `core/ds/atomicLazy.ml` | `src/core/ds/AtomicLazy.hx` | Translated (audited); a mutex in place of compare-and-set, waiting sleeps instead of `Thread.yield`/`Backoff` |
| `core/ds/nowOrLater.ml` | `src/core/ds/NowOrLater.hx` | Translated (audited); a flag emulates the non-recursive OCaml mutex |
| `core/ds/priorityQueue.ml` | `src/core/ds/PriorityQueue.hx` | Translated (audited) |
| `core/ds/ring.ml` | `src/core/ds/Ring.hx` | Translated (audited) |
| `core/ds/stringDynArray.ml` | `src/core/ds/StringDynArray.hx` | Translated (audited) |
| `core/ds/stringPool.ml` | `src/core/ds/StringPool.hx` | Translated (audited); NUL-safe keys on HashLink |
| `core/ds/threadSafeHashtbl.ml` | `src/core/ds/ThreadSafeHashtbl.hx` | Translated (audited); an `OcamlHashtbl` (String and Int keys) behind a mutex |
| `core/error.ml` | `src/core/Error.hx` | Draft translated |
| `core/globals.ml` | `src/core/Globals.hx` | Translated (audited); the map/table modules are in `core.ds`, `trace` and the backtrace helpers use the Haxe call stack |
| `core/inheritDoc.ml` | `src/core/InheritDoc.hx` | Draft translated |
| `core/message.ml` | `src/core/Message.hx` | Translated (audited); also declares the generated `warning` type (`WarningCode`) |
| `core/meta.ml` | `src/core/Meta.hx` | Draft translated |
| `core/naming.ml` | `src/core/Naming.hx` | Draft translated |
| `core/native.ml` | `src/core/Native.hx` | Draft translated |
| `core/numeric.ml` | `src/core/Numeric.hx` | Translated (audited); adds `stringOfFloat` (OCaml `string_of_float`) |
| `core/path.ml` | `src/core/Path.hx` | Translated (audited); `get_full_path`/`get_real_path` on Windows use `FileSystem.fullPath` in place of Extc |
| `core/socket.ml` | `src/core/Socket.hx` | Translated (audited, also with the Eval debugger); host sockets read whole frames (exact lengths) where `recv` may return fewer bytes |
| `core/stringError.ml` | `src/core/StringError.hx` | Translated (audited); two-row Levenshtein over UTF-8 bytes |
| `core/stringHelper.ml` | `src/core/StringHelper.hx` | Translated (audited); byte strings are strings of characters 0-255 |
| `core/tFunctions.ml` | `src/core/TFunctions.hx` | Draft translated |
| `core/tOther.ml` | `src/core/TOther.hx` | Draft translated |
| `core/tPrinting.ml` | `src/core/TPrinting.hx` | Draft translated |
| `core/tType.ml` | `src/core/TType.hx` | Translated (audited); PMap fields are StringMaps iterated through `core.ds.PMap` |
| `core/tUnification.ml` | `src/core/TUnification.hx` | Draft translated |
| `core/texpr.ml` | `src/core/Texpr.hx` | Draft translated |
| `core/timer.ml` | `src/core/Timer.hx` | Draft translated |
| `core/type.ml` | `src/core/Type.hx` | Draft translated |
| `core/warning.ml` | `src/core/Warning.hx` | Draft translated |
| `core/withType.ml` | `src/core/WithType.hx` | Draft translated |
| `core/zip_output.ml` | `src/core/ZipOutput.hx` | Translated (audited); `Zip` over `haxe.zip.Writer`, written on close |
| `coro/contTypes.ml` | `src/coro/ContTypes.hx` | Draft translated |
| `coro/coro.ml` | `src/coro/Coro.hx` | Draft translated |
| `coro/coroConfig.ml` | `src/coro/CoroConfig.hx` | Draft translated |
| `coro/coroControl.ml` | `src/coro/CoroControl.hx` | Draft translated |
| `coro/coroDebug.ml` | `src/coro/CoroDebug.hx` | Draft translated |
| `coro/coroElsewhere.ml` | `src/coro/CoroElsewhere.hx` | Draft translated |
| `coro/coroFromTexpr.ml` | `src/coro/CoroFromTexpr.hx` | Draft translated |
| `coro/coroFunctions.ml` | `src/coro/CoroFunctions.hx` | Draft translated |
| `coro/coroInit.ml` | `src/coro/CoroInit.hx` | Draft translated |
| `coro/coroScopeConfig.ml` | `src/coro/CoroScopeConfig.hx` | Draft translated |
| `coro/coroToTexpr.ml` | `src/coro/CoroToTexpr.hx` | Draft translated |
| `coro/coroTypes.ml` | `src/coro/CoroTypes.hx` | Draft translated |
| `filters/exception/exceptionFunctions.ml` | `src/filters/exception/ExceptionFunctions.hx` | Draft translated |
| `filters/exception/exceptionInit.ml` | `src/filters/exception/ExceptionInit.hx` | Draft translated |
| `filters/exception/exceptions.ml` | `src/filters/exception/Exceptions.hx` | Draft translated |
| `filters/exception/saveStacks.ml` | `src/filters/exception/SaveStacks.hx` | Draft translated |
| `filters/filterContext.ml` | `src/filters/FilterContext.hx` | Draft translated |
| `filters/filters.ml` | `src/filters/Filters.hx` | Draft translated |
| `filters/filtersCommon.ml` | `src/filters/FiltersCommon.hx` | Draft translated |
| `filters/localUsage.ml` | `src/filters/LocalUsage.hx` | Draft translated |
| `filters/renameVars.ml` | `src/filters/RenameVars.hx` | Draft translated |
| `filters/safe/addFieldInits.ml` | `src/filters/safe/AddFieldInits.hx` | Draft translated |
| `filters/safe/addFinalReturn.ml` | `src/filters/safe/AddFinalReturn.hx` | Draft translated |
| `filters/safe/capturedVars.ml` | `src/filters/safe/CapturedVars.hx` | Draft translated |
| `filters/safe/checkVarInit.ml` | `src/filters/safe/CheckVarInit.hx` | Draft translated |
| `filters/safe/localStatic.ml` | `src/filters/safe/LocalStatic.hx` | Draft translated |
| `filters/safe/safeFilters.ml` | `src/filters/safe/SafeFilters.hx` | Draft translated |
| `filters/safe/sanitize.ml` | `src/filters/safe/Sanitize.hx` | Draft translated |
| `filters/tre.ml` | `src/filters/Tre.hx` | Draft translated |
| `optimization/analyzer.ml` | `src/optimization/Analyzer.hx` | Draft translated |
| `optimization/analyzerConfig.ml` | `src/optimization/AnalyzerConfig.hx` | Draft translated |
| `optimization/analyzerTexpr.ml` | `src/optimization/AnalyzerTexpr.hx` | Draft translated |
| `optimization/analyzerTexprTransformer.ml` | `src/optimization/AnalyzerTexprTransformer.hx` | Draft translated |
| `optimization/analyzerTypes.ml` | `src/optimization/AnalyzerTypes.hx` | Draft translated |
| `optimization/dce.ml` | `src/optimization/Dce.hx` | Draft translated |
| `optimization/inline.ml` | `src/optimization/Inline.hx` | Draft translated |
| `optimization/inlineConstructors.ml` | `src/optimization/InlineConstructors.hx` | Draft translated |
| `optimization/optimizer.ml` | `src/optimization/Optimizer.hx` | Draft translated |
| `optimization/optimizerTexpr.ml` | `src/optimization/OptimizerTexpr.hx` | Draft translated |
| `syntax/grammar.ml` | `src/syntax/Grammar.hx` | Translated (audited); ppx_parser stream semantics reproduced by hand (see the file header); `parse_obj_decl` defers its missing-`:` errors as upstream's argument evaluation does |
| `syntax/lexer.ml` | `src/syntax/Lexer.hx` | Translated (audited). Deviation: sedlex rules are a hand-written longest-match scanner over UTF-16 with code-point positions; newlines are recorded after each token; `Ast.unescape` lives here and works on UTF-8 bytes; `Invalid_option` is `InvalidRegexpOption` |
| `syntax/parser.ml` | `src/syntax/Parser.hx` | Draft translated |
| `syntax/parserConfig.ml` | `src/syntax/ParserConfig.hx` | Draft translated |
| `syntax/parserEntry.ml` | `src/syntax/ParserEntry.hx` | Draft translated |
| `syntax/reification.ml` | `src/syntax/Reification.hx` | Draft translated |
| `syntax/semver.ml` | `src/syntax/SemVer.hx` | Translated (audited); `SVNum` holds the 63-bit OCaml int as `Int64` |
| `typing/callUnification.ml` | `src/typing/CallUnification.hx` | Draft translated |
| `typing/calls.ml` | `src/typing/Calls.hx` | Draft translated |
| `typing/fieldAccess.ml` | `src/typing/FieldAccess.hx` | Draft translated |
| `typing/fieldCallCandidate.ml` | `src/typing/FieldCallCandidate.hx` | Draft translated |
| `typing/fields.ml` | `src/typing/Fields.hx` | Draft translated |
| `typing/finalization.ml` | `src/typing/Finalization.hx` | Draft translated |
| `typing/forLoop.ml` | `src/typing/ForLoop.hx` | Draft translated |
| `typing/functionArguments.ml` | `src/typing/FunctionArguments.hx` | Draft translated |
| `typing/generic.ml` | `src/typing/Generic.hx` | Draft translated |
| `typing/instanceBuilder.ml` | `src/typing/InstanceBuilder.hx` | Draft translated |
| `typing/matcher/bind.ml` | `src/typing/matcher/Bind.hx` | Draft translated |
| `typing/matcher/case.ml` | `src/typing/matcher/Case.hx` | Draft translated |
| `typing/matcher/compile.ml` | `src/typing/matcher/Compile.hx` | Draft translated |
| `typing/matcher/constructor.ml` | `src/typing/matcher/Constructor.hx` | Draft translated |
| `typing/matcher/decisionTree.ml` | `src/typing/matcher/DecisionTree.hx` | Draft translated |
| `typing/matcher/exprToPattern.ml` | `src/typing/matcher/ExprToPattern.hx` | Draft translated |
| `typing/matcher/matcherGlobals.ml` | `src/typing/matcher/MatcherGlobals.hx` | Draft translated |
| `typing/matcher/pattern.ml` | `src/typing/matcher/Pattern.hx` | Draft translated |
| `typing/matcher/subject.ml` | `src/typing/matcher/Subject.hx` | Draft translated |
| `typing/matcher/texprConverter.ml` | `src/typing/matcher/TexprConverter.hx` | Draft translated |
| `typing/matcher/useless.ml` | `src/typing/matcher/Useless.hx` | Draft translated |
| `typing/matcher.ml` | `src/typing/Matcher.hx` | Draft translated |
| `typing/nullSafety.ml` | `src/typing/NullSafety.hx` | Draft translated |
| `typing/operators.ml` | `src/typing/Operators.hx` | Draft translated |
| `typing/overloadResolution.ml` | `src/typing/OverloadResolution.hx` | Draft translated |
| `typing/strictMeta.ml` | `src/typing/StrictMeta.hx` | Draft translated |
| `typing/tanon_identification.ml` | `src/typing/TanonIdentification.hx` | Draft translated |
| `typing/typeload.ml` | `src/typing/Typeload.hx` | Draft translated |
| `typing/typeloadCacheHook.ml` | `src/typing/TypeloadCacheHook.hx` | Translated (also used by `MacroContext` for fake modules) |
| `typing/typeloadCheck.ml` | `src/typing/TypeloadCheck.hx` | Draft translated |
| `typing/typeloadFields.ml` | `src/typing/TypeloadFields.hx` | Draft translated |
| `typing/typeloadFunction.ml` | `src/typing/TypeloadFunction.hx` | Draft translated |
| `typing/typeloadModule.ml` | `src/typing/TypeloadModule.hx` | Source pipeline integrated during compile phase; `hxb_reader_api_typeload` and `load_hxb_module` translated (the legacy bootstrap loader is in `archive/legacy-bootstrap/`) |
| `typing/typeloadParse.ml` | `src/typing/TypeloadParse.hx` | Source pipeline integrated during compile phase |
| `typing/typer.ml` | `src/typing/Typer.hx` | Draft translated |
| `typing/typerBase.ml` | `src/typing/TyperBase.hx` | Draft translated |
| `typing/typerDotPath.ml` | `src/typing/TyperDotPath.hx` | Draft translated |
| `typing/typerEntry.ml` | `src/typing/TyperEntry.hx` | Draft translated |
| `typing/unifyMin.ml` | `src/typing/UnifyMin.hx` | Draft translated |

## Additional shared source coverage

| Upstream under `haxe/src/` | Haxe counterpart | Scope |
| --- | --- | --- |
| `context/display/deprecationCheck.ml` | `src/context/display/DeprecationCheck.hx` | Compiler warnings |
| `context/display/importHandling.ml` | `src/context/display/ImportHandling.hx` | Batch imports and using resolution |
| `core/display/displayPosition.ml` | `src/core/display/DisplayPosition.hx` | Shared position state |
| `core/display/javadoc.ml` | `src/core/display/Javadoc.hx` | Documentation parsing |
| `codegen/genxml.ml` | `src/codegen/Genxml.hx` | RTTI serializer and `--xml` output; byte-identical (fuzzer, `extra/doc.hxml` for every target, upstream unit suite) |
| `compiler/compilationCache.ml` | `src/compiler/CompilationCache.hx` | Server cache |
| `compiler/pipeThings.ml` | `src/compiler/PipeThings.hx` | Client/server transport (host streams, see header) |
| `compiler/tasks.ml` | `src/compiler/Tasks.hx` | Server maintenance tasks |
| `compiler/server/server.ml` | `src/compiler/server/Server.hx` | Server loop, `--connect`, `--server-connect` |
| `compiler/server/serverCache.ml` | `src/compiler/server/ServerCache.hx` | Module cache, `hxb_reader_api_server` |
| `compiler/server/serverCompilationContext.ml` | `src/compiler/server/ServerCompilationContext.hx` | Server context |
| `compiler/server/serverConfig.ml` | `src/compiler/server/ServerConfig.hx` | Server configuration |
| `compiler/server/serverMessage.ml` | `src/compiler/server/ServerMessage.hx` | Verbose server messages |
| `context/commonCache.ml` | `src/context/CommonCache.hx` | Cache contexts and signatures |
| `compiler/displayOutput.ml` | `src/compiler/DisplayOutput.hx` | Display services |
| `compiler/displayProcessing.ml` | `src/compiler/DisplayProcessing.hx` | Display services |
| `compiler/displayProcessingGlobals.ml` | `src/compiler/DisplayProcessingGlobals.hx` | Display services |
| `context/display/diagnostics.ml` | `src/context/display/Diagnostics.hx` | Display services |
| `context/display/diagnosticsPrinter.ml` | `src/context/display/DiagnosticsPrinter.hx` | Display services |
| `context/display/display.ml` | `src/context/display/Display.hx` | Display services |
| `context/display/displayEmitter.ml` | `src/context/display/DisplayEmitter.hx` | Display services |
| `context/display/displayException.ml` | `src/context/display/DisplayException.hx` | Display services |
| `context/display/displayFields.ml` | `src/context/display/DisplayFields.hx` | Display services |
| `context/display/displayJson.ml` | `src/context/display/DisplayJson.hx` | Display services, `server/*` methods (`test/server-jsonrpc.py`) |
| `context/display/displayMemory.ml` | `src/context/display/DisplayMemory.hx` | Translated; sizes as the host measures them (see `Memory.hx`) |
| `context/display/displayPath.ml` | `src/context/display/DisplayPath.hx` | Display services |
| `context/display/displayTexpr.ml` | `src/context/display/DisplayTexpr.hx` | Display services |
| `context/display/displayToplevel.ml` | `src/context/display/DisplayToplevel.hx` | Display services |
| `context/display/documentSymbols.ml` | `src/context/display/DocumentSymbols.hx` | Display services |
| `context/display/exprPreprocessing.ml` | `src/context/display/ExprPreprocessing.hx` | Display services |
| `context/display/findReferences.ml` | `src/context/display/FindReferences.hx` | Display services |
| `context/display/statistics.ml` | `src/context/display/Statistics.hx` | Display services |
| `context/display/syntaxExplorer.ml` | `src/context/display/SyntaxExplorer.hx` | Display services |
| `context/memory.ml` | `src/context/Memory.hx` | Translated; `Objsize` is the host's heap walk (hxc), 0 elsewhere |
| `core/display/completionItem.ml` | `src/core/display/CompletionItem.hx` | Display services |
| `core/json/genjson.ml` | `src/core/json/Genjson.hx` | Display serialization and `--json` output; byte-identical (fuzzer, `extra/doc.hxml` set, upstream unit suite); `generate_module` is in the server (`DisplayJson`) |
| `core/json/jsonRpc.ml` | `src/core/json/JsonRpc.hx` | JSON-RPC protocol |
| `core/json/jsonRpcSocket.ml` | `src/core/json/JsonRpcSocket.hx` | Eval debugger transport |
| `core/json/jsonrpc_handler.ml` | `src/core/json/JsonrpcHandler.hx` | JSON-RPC handler |
| `typing/typerDisplay.ml` | `src/typing/TyperDisplay.hx` | Display services |

## Target generator coverage

Every generator's output is byte-identical to the reference compiler's on the
differential fuzzer's `diff:<target>` lane (`test/fuzz`; see `test/TESTING.md`)
and on the hand and upstream cases listed there. Generated programs are not run.

| Upstream under `haxe/src/` | Port | Notes |
| --- | --- | --- |
| `compiler/generate.ml` (dispatch) | `src/compiler/Generate.hx` | Translated |
| `generators/gctx.ml` | `src/generators/Gctx.hx` | Translated |
| `generators/genshared.ml` | `src/generators/Genshared.hx` | Translated (JVM) |
| `generators/genhxold.ml` | `src/generators/Genhxold.hx` | `--xml hx` / `-D gen-hx-classes` extern output (`hxclasses/`); byte-identical on the fuzzer and the `extra/ImportAll` std set for every target |
| `filters/ES6Ctors.ml` | `src/filters/ES6Ctors.hx` | JS, `-D js-es=6` |
| `generators/genjs.ml` | `src/generators/Genjs.hx` | JS; `.js` and `.map` byte-identical, also the upstream unit suite and `tests/misc/js` |
| `generators/jsSourcemap.ml` | `src/generators/JsSourcemap.hx` | JS and Lua source maps (columns in UTF-8 bytes) |
| `context/sourcemaps.ml` | `src/context/Sourcemaps.hx` | PHP source maps |
| `generators/genlua.ml` | `src/generators/Genlua.hx` | Lua |
| `generators/genpy.ml` | `src/generators/Genpy.hx` | Python |
| `generators/genphp7.ml` | `src/generators/Genphp7.hx`, `src/generators/genphp7/` | PHP |
| `generators/genneko.ml` | `src/generators/Genneko.hx` | Neko; `libs/neko/*.ml` in `src/libs/neko/`; `nekoc` arguments quoted as upstream 995a7d1fe (Unix `Filename.quote`) |
| `generators/genhl.ml` | `src/generators/Genhl.hx` | HashLink bytecode; at upstream 995a7d1fe (`lookup` maps and `check` in `Hashtbl` order, `rec_cache` retry, `BaseType.downcast`) |
| `generators/hlcode.ml`, `hlopt.ml` | `src/generators/Hlcode.hx`, `Hlopt.hx` | HashLink; `hlopt` at upstream 995a7d1fe (null-check folding, backward unused `mov`/`null` pass) |
| `generators/hl2c.ml` | `src/generators/Hl2c.hx` | HL/C; type names hashed from a reproduction of OCaml's `Marshal`; descriptors that marshal a closure fail explicitly; at upstream 995a7d1fe (`memcpy` byte access) |
| `generators/hlinterp.ml` | `src/generators/Hlinterp.hx` | complete (values, interpreter loop, `std` natives, error/stack reporting, `check`; `--hl x.hl -D interp` runs the bytecode; the commented-out SPEC section is kept as a comment); OCaml `Str` (used by the regexp natives) is `src/core/ds/OcamlStr.hx` |
| `generators/genjvm.ml`, `generators/jvm/*.ml` | `src/generators/Genjvm.hx`, `src/generators/jvm/` | JVM (sequential passes, as upstream with `-D disable-parallelism`); at upstream 995a7d1fe (overriding dynamic methods share the parent's field) |
| `codegen/javaModern.ml` | `src/codegen/JavaModern.hx` | Java library input (`hxjava-std.jar`, `--java-lib`) |
| `generators/gencpp.ml`, `generators/cpp/**/*.ml` | `src/generators/Gencpp.hx`, `src/generators/cpp/` | C++ and cppia; at upstream 995a7d1fe (`override` specifiers) |
| `generators/genswf.ml`, `genswf9.ml`, `flashProps.ml` | `src/generators/Genswf.hx`, `Genswf9.hx`, `FlashProps.hx` | SWF/SWC, including `--swf-lib` merging, PNG `@:bitmap` and JPEG+PNG-alpha bitmaps; at upstream 995a7d1fe (rest-argument spread order; `swfParser.ml` changed only labels) |
| `codegen/swfLoader.ml` | `src/codegen/SwfLoader.hx` | SWF/SWC/ANE library input (`--swf-lib`, `--swf-lib-extern`): extern classes, `enumAbstract:` defines, `@:bind` class removal |

OCaml library code the generators need, reproduced under `src/libs/`: `neko`
(AST, bytecode compiler and writer), `swflib` (SWF, AS2 action and ABC
readers and writers, `as3hlparse` parse/flatten, `png` reading; `swfPic` and
the dump printers have no compiler caller), `extc` (zlib 1.3.1 deflate,
translated so compressed SWF output is byte-identical; inflate over the std's
`haxe.zip.InflateImpl`, deterministic for valid streams), `extlib` (`IO`
readers and writers) and `ziplib` (SWC ZIP writer; reading in
`src/core/ZipInput.hx`).

## Macro runtime coverage

Conventions: `src/macros/PORTING.md`. Natives without a host implementation
fail with "... is not supported by haxe-in-haxe".

| Upstream under `haxe/src/` | Haxe counterpart | Status |
| --- | --- | --- |
| `macro/eval/bytes/evalBytesLower.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/bytes/evalBytesUpper.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/bytes/evalBytes_E_L79.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/bytes/evalBytes_L1020.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/bytes/evalBytes_U1021.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/bytes/evalBytes_U79.ml` | `src/macros/eval/EvalBytesUnicase.hx` | Translated (case tables) |
| `macro/eval/eval.ml` | `src/macros/eval/EvalMain.hx` | Only includes other modules |
| `macro/eval/evalArray.ml` | `src/macros/eval/EvalArray.hx` | Translated |
| `macro/eval/evalAtomic.ml` | `src/macros/eval/EvalAtomic.hx` | Translated |
| `macro/eval/evalBytes.ml` | `src/macros/eval/EvalBytesUnicase.hx`; byte access in `EvalStdLibA.hx` | Translated |
| `macro/eval/evalContext.ml` | `src/macros/eval/EvalContext.hx` | Translated |
| `macro/eval/evalDataApi.ml` | `src/macros/eval/EvalDataApi.hx` | Translated |
| `macro/eval/evalDebug.ml` | `src/macros/eval/EvalDebug.hx` | Translated (`test/eval-debugger.py`) |
| `macro/eval/evalDebugMisc.ml` | `src/macros/eval/EvalDebugMisc.hx` | Translated |
| `macro/eval/evalDebugSocket.ml` | `src/macros/eval/EvalDebugSocket.hx` | Translated; `getCompletion` kills the debugger thread as upstream's does |
| `macro/eval/evalDecode.ml` | `src/macros/eval/EvalDecode.hx` | Translated |
| `macro/eval/evalEmitter.ml` | `src/macros/eval/EvalEmitter.hx` | Translated |
| `macro/eval/evalEncode.ml` | `src/macros/eval/EvalEncode.hx` | Translated |
| `macro/eval/evalExceptions.ml` | `src/macros/eval/EvalExceptions.hx` | Translated |
| `macro/eval/evalField.ml` | `src/macros/eval/EvalField.hx` | Translated |
| `macro/eval/evalHash.ml` | `src/macros/eval/EvalHash.hx` | Translated |
| `macro/eval/evalIntegers.ml` | `src/macros/eval/EvalIntegers.hx` | Translated |
| `macro/eval/evalJit.ml` | `src/macros/eval/EvalJit.hx` | Translated |
| `macro/eval/evalJitContext.ml` | `src/macros/eval/EvalJitContext.hx` | Translated |
| `macro/eval/evalLuv.ml` | `src/macros/eval/EvalLuv.hx` | Translated; libuv through `hxc.NativeUv` (hxc host only); threads, thread pool and synchronization on host threads |
| `macro/eval/evalMain.ml` | `src/macros/eval/EvalMain.hx` | Translated |
| `macro/eval/evalMisc.ml` | `src/macros/eval/EvalMisc.hx` | Translated |
| `macro/eval/evalPrinting.ml` | `src/macros/eval/EvalPrinting.hx` | Translated |
| `macro/eval/evalPrototype.ml` | `src/macros/eval/EvalPrototype.hx` | Translated |
| `macro/eval/evalSsl.ml` | `src/macros/eval/EvalSsl.hx` | Translated; mbedtls through `hxc.NativeSsl` (hxc host only) |
| `macro/eval/evalStackTrace.ml` | `src/macros/eval/EvalStackTrace.hx` | Translated |
| `macro/eval/evalStdLib.ml` | `src/macros/eval/EvalStdLib.hx`, `EvalStdLibA.hx`, `EvalStdLibB.hx` | Translated; host processes in `EvalProcess.hx` (`libs/extc/process.ml`), HashLink sockets in `EvalHostNet.hx` |
| `macro/eval/evalString.ml` | `src/macros/eval/EvalString.hx` | Translated |
| `macro/eval/evalThread.ml` | `src/macros/eval/EvalThread.hx` | Translated; Eval threads serialized by `EvalLock.hx` |
| `macro/eval/evalTypes.ml` | `src/macros/eval/EvalTypes.hx` | Translated |
| `macro/eval/evalValue.ml` | `src/macros/eval/EvalValue.hx` | Translated |
| `macro/macroApi.ml` | `src/macros/MacroApi.hx` | Translated |
| `typing/macroContext.ml` | `src/typing/MacroContext.hx` | Translated |

## Deferred or scope-review areas

These entries are recorded so absence is not mistaken for a completed translation.
A scope-review entry is not a blanket exclusion of shared batch-compiler helpers.

| Upstream under `haxe/src/` | Reason |
| --- | --- |
| `codegen/jClass.ml` | Not needed: upstream uses it only as the type of `java_lib_type` (`nativeLibraries.ml`), whose only producer, `JavaModern`'s `lookup`, always returns `None`; the port keeps that payload opaque (`NativeLibraries.JavaClassData`) |
| `lazy.ml` | OCaml build/runtime adapter; no mechanical compiler-module port |
| `prebuild.ml` | OCaml build/runtime adapter; no mechanical compiler-module port |

## Additional draft support files

- `src/core/MetaList.hx`
- `src/core/WarningList.hx`
- `src/macros/eval/EvalLock.hx`: OCaml's runtime lock for Eval threads on host
  threads (no upstream module; see its comment)

## Next work

Every upstream module now has a counterpart or a recorded reason. What
remains open:

