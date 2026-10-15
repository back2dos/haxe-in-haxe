# haxe-in-haxe: builds the reference compiler, hxmc (the machine-code target,
# hxmc/README.md), the port with hxmc for the host and as release binaries for
# six targets, the website's WebAssembly, lix and the fuzzer. GNU make, from
# the repository root.
#
#   make help                 the targets and variables below
#   make reference            haxe/haxe, the reference compiler (OCaml 5, opam)
#   make bootstrap            bin/hxmc/hxmc, the first hxmc tool (from the reference and node)
#   make port                 bin/port/haxe: the port built by hxmc (seconds after an edit)
#   make test                 HXB conformance of bin/port/haxe
#   make quick|check|full     hxmc's tiered checks (hxmc/tools/tiers.py)
#   make release TARGET=macos-arm64   bin/release/<TARGET>/haxe-in-haxe[.exe]
#
# Outputs go to bin/ (ignored by Git). hxmc keeps an object per module next to
# each output (<out>.hxmc/) and recompiles only the modules that changed.

# --- Variables (override on the command line: make release TARGET=windows-arm64) ---

# the reference compiler: writes the bootstrap's JavaScript and the HXB of test programs
HAXE ?= haxe/haxe
# the upstream std, for every compiler run below
export HAXE_STD_PATH ?= $(CURDIR)/haxe/std
JOBS ?= $(shell nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
# the bootstrap runs the tool as JavaScript: node and hxnodejs (without
# haxelib, e.g. in CI: TOOL_LIBS="<clone>/extraParams.hxml -cp <clone>/src")
NODE ?= node
TOOL_LIBS ?= -lib hxnodejs
ZIG ?= zig
export ZIG
# the machine the tool runs on (Linux; its own runtime object)
HOST ?= linux-$(if $(filter aarch64 arm64,$(shell uname -m)),arm64,x86_64)
# `make release`, `make lix-release`: one of the six targets
TARGET ?= $(HOST)
# the targets whose runtime objects `make rt` builds
RT_TARGETS ?= linux-x86_64 linux-arm64 windows-x86_64 windows-arm64 macos-x86_64 macos-arm64
# extra arguments of the port's build (e.g. HXFLAGS="-D retain")
HXFLAGS ?=
# the port tested by `make test`, `make test-fuzz`
PORT_BIN ?= bin/port/haxe
# `make smoke`: the binary to check
SMOKE_BIN ?= $(PORT_BIN)
# `make test-fuzz`: the lane and the number of programs
LANE ?= diff:hxb
N ?= 200
# `make hxmc-test`: extra arguments of hxmc/tools/run.py (e.g. RUN_ARGS="--target linux-arm64")
RUN_ARGS ?=
# `quick`, `check`, `full`: the corpus cases to restrict the corpus lanes to
# (CASES="Int64Gc Bench"); PORT=1 adds the port's self-compile to `check`
CASES ?=
PORT ?=
# the site's scripts are compiled by SITE_HAXE (the port works too)
SITE_HAXE ?= $(HAXE)
# `make site`: a directory of lix binaries to publish under tools/ (lix-<target>[.exe])
LIX_DIR ?=
# lix (tools/lix): hxcoro's checkout (fetched at HXCORO_REV unless it exists)
HXCORO ?= bin/hxcoro

# --- Sources ---

PORT_SRC := $(shell find src -name '*.hx')
HXMC_SRC := $(shell find hxmc/src -name '*.hx')
STD_SRC := $(shell find hxmc/std -type f)
RT_SRC := $(wildcard hxmc/rt/*.c hxmc/rt/*.h)
BOOT_SRC := $(shell find hxmc/tools/bootstrap/js -name '*.hx')
LIX_SRC := $(shell find tools/lix/src -name '*.hx')
FUZZ_SRC := $(wildcard test/fuzz/*.hx test/fuzz/fuzz/*.hx)
SITE_SRC := $(wildcard site/src/*.hx site/*.html site/*.css site/js/*)

STD := bin/hxmc/std/.stamp
HOST_RT := bin/hxmc/rt/$(HOST)/rt.o
TOOL := bin/hxmc/hxmc
# the hxmc target: bin/hxmc/std (hxmc/std merged with the Eval originals for
# macros), given last
HXMC_ARGS := -cp bin/hxmc/std --custom-target hxmc
# the tool is the port (src) with hxmc (hxmc/src) as its generate hook, typed
# against hxmc's std, without the port's other target generators
TOOL_CP := -cp src -cp hxmc/src -main hxmc.Main -D disable-parallelism -D hih_no_generators -cp bin/hxmc/std
TOOL_ARGS := $(TOOL_CP) --custom-target hxmc
# the port (typed with -D disable-parallelism; the binary runs its parallel
# passes unless its own invocation passes that define)
PORT_ARGS := -cp src -main haxe.Main -D disable-parallelism $(HXFLAGS) $(HXMC_ARGS)
EXE = $(if $(findstring windows,$(1)),.exe)
RELEASE_BIN := bin/release/$(TARGET)/haxe-in-haxe$(call EXE,$(TARGET))
LIX_BIN := bin/release/$(TARGET)/lix$(call EXE,$(TARGET))

# $(call hxmc,<out>,<args>): a build by the tool, its log next to the output
define hxmc
@mkdir -p $(dir $(1))
ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(1) $(2) > $(1).log 2>&1 || { cat $(1).log; exit 1; }
@ls -l $(1)
endef

.DEFAULT_GOAL := help
.PHONY: help reference std deps rt hxmc tool bootstrap fixpoint port dev release wasm site fuzz \
	lix lix-release test test-fuzz smoke hxmc-test portcheck quick check full clean distclean

help:
	@sed -n '/^# --- Targets/,$$p' $(MAKEFILE_LIST) | sed -n 's/^## \{0,1\}//p'

# --- Targets ---
## reference   haxe/haxe, the reference compiler (make -C haxe haxe; needs OCaml 5, opam, pcre2)
## std         bin/hxmc/std: hxmc/std merged with the Eval originals (hxmc/tools/mkstd.py)
## deps        bin/hxmc/deps/TARGET: mbedtls and libuv for TARGET (hxmc/tools/deps.sh, zig cc)
## rt          the runtime objects of RT_TARGETS (bin/hxmc/rt/<target>/rt.o, ssl.o, uv.o; zig cc)
## hxmc        bin/hxmc/hxmc: the tool, built by the previous tool from source (alias: tool)
## bootstrap   the tool from scratch: the reference compiler writes the tool's JavaScript
##             and its HXB, node compiles the HXB to bin/hxmc/boot/hxmc1, which builds bin/hxmc/hxmc
## fixpoint    bin/hxmc/hxmc builds bin/hxmc/fix/a, which builds bin/hxmc/fix/b: byte-identical
## port        PORT_BIN (bin/port/haxe): the port for the host, built by hxmc (alias: dev)
## release     bin/release/TARGET/haxe-in-haxe[.exe]: the port cross-built by hxmc, with mbedtls and libuv
## wasm        bin/wasm/hih.wasm: the playground's compiler (wasm32-wasi, -D hih_no_generators)
## site        bin/site: the website (wasm, the std bundle, pages, their scripts compiled by
##             SITE_HAXE; LIX_DIR's lix binaries under tools/)
## fuzz        bin/fuzz/fuzz: the differential fuzzer, built by hxmc
## lix         bin/lix/lix (+ haxe, haxelib, neko links): lix (tools/lix) for the host
## lix-release bin/release/TARGET/lix[.exe]: lix cross-built for TARGET
## test        HXB conformance of PORT_BIN against the reference (test/conformance.py)
## test-fuzz   the fuzzer on PORT_BIN: LANE (default diff:hxb), N programs
## smoke       tools/smoke.sh on SMOKE_BIN (default PORT_BIN): --interp, HXB, JS, sys.ssl, eval.luv
## hxmc-test   hxmc's corpus against its golden files (hxmc/tools/run.py, RUN_ARGS)
## portcheck   the port built by hxmc self-compiles to the reference's HXB (hxmc/tools/portcheck.sh)
## quick       after every edit (under a minute): the tool, then the x64 corpus, again with
##             RT_VERIFY=1, and the wasm corpus under node (CASES restricts the corpus)
## check       before a local commit (a few minutes): quick + arm64 (qemu), wine, a 16 KB
##             nursery, ThreadNatives x30; PORT=1 adds the native port's self-compile
## full        before a push: every nursery, RT_VERIFY, wasmtime, ThreadNatives x300, the
##             port's self-compile natively and as a module, the fixpoint
## clean       remove the build outputs (keeps the tool, bin/hxmc/deps and the reference)
## distclean   also remove bin/ entirely
##
## Variables: HAXE, HAXE_STD_PATH, JOBS, NODE, TOOL_LIBS, ZIG, HOST, TARGET, RT_TARGETS, HXFLAGS,
## PORT_BIN, SMOKE_BIN, LANE, N, RUN_ARGS, CASES, PORT, SITE_HAXE, LIX_DIR, HXCORO
## (defaults and meaning: the top of the Makefile).

reference:
	$(MAKE) -C haxe -j$(JOBS) haxe

std: $(STD)
$(STD): hxmc/tools/mkstd.py $(STD_SRC)
	python3 hxmc/tools/mkstd.py

# --- hxmc: the tool and its runtime objects ---

# mbedtls and libuv per target (rebuilt only when their versions or flags
# change), for the runtime's ssl.o and uv.o
deps: bin/hxmc/deps/$(TARGET)/VERSIONS
.PRECIOUS: bin/hxmc/deps/%/VERSIONS
bin/hxmc/deps/%/VERSIONS: hxmc/tools/deps.sh
	sh hxmc/tools/deps.sh $* bin/hxmc/deps/$*
	touch $@

# the host's runtime object needs no hxmc (Linux: zig cc and ld.lld); the
# Windows and macOS ones are assembled by the tool (hxmc --mkrt)
$(HOST_RT): hxmc/tools/mkrt.sh $(RT_SRC) bin/hxmc/deps/$(HOST)/VERSIONS
	sh hxmc/tools/mkrt.sh $(HOST)
.PRECIOUS: bin/hxmc/rt/%/rt.o
bin/hxmc/rt/%/rt.o: $(TOOL) hxmc/tools/mkrt.sh $(RT_SRC) bin/hxmc/deps/%/VERSIONS
	sh hxmc/tools/mkrt.sh $*

rt: $(foreach t,$(RT_TARGETS),bin/hxmc/rt/$(t)/rt.o)

# The tool compiles its own source with the previous tool (written next to it,
# then moved: the running binary is replaced). A change to code generation
# reaches the tool's own code on the next rebuild (`fixpoint` checks that a
# rebuild changes nothing).
hxmc tool: $(TOOL)
$(TOOL): $(PORT_SRC) $(HXMC_SRC) $(STD) $(HOST_RT)
	@if [ ! -x $@ ]; then $(MAKE) bin/hxmc/boot/hxmc1; fi
	@T=$@; [ -x $$T ] || T=bin/hxmc/boot/hxmc1; \
	echo "$$T $@.new $(TOOL_ARGS)"; \
	ulimit -s unlimited 2>/dev/null || true; \
	HXMC_RT_OBJ=$(CURDIR)/$(HOST_RT) $$T $@.new $(TOOL_ARGS) > bin/hxmc/tool.log 2>&1 || { cat bin/hxmc/tool.log; exit 1; }
	mv $@.new $@
	rm -rf $@.new.hxmc
	ls -l $@

bootstrap:
	rm -f $(TOOL) bin/hxmc/boot/hxmc1
	$(MAKE) $(TOOL)

# the bootstrap: the tool as JavaScript (the port runs on node; the
# sys.thread and sys.net stand-ins of hxmc/tools/bootstrap/js, given last)
bin/hxmc/boot/hxmc.js: $(PORT_SRC) $(HXMC_SRC) $(BOOT_SRC)
	@mkdir -p $(dir $@)
	$(HAXE) -cp src -cp hxmc/src -main hxmc.Main $(TOOL_LIBS) -cp hxmc/tools/bootstrap/js -D hih_no_generators --js $@ -w -WDeprecated

bin/hxmc/boot/hxmc.hxb.zip: $(PORT_SRC) $(HXMC_SRC) $(STD)
	@mkdir -p $(dir $@)
	$(HAXE) $(TOOL_CP) --custom-target hxmc=bin/hxmc/boot/x --hxb $@ --no-output -w -WUnusedPattern

# one thread, no restart with GC settings (HXMC_GC_DEFAULTS=0: the tool
# would run itself again); hxnodejs' stdout flush fails on pipes: a log file
bin/hxmc/boot/hxmc1: bin/hxmc/boot/hxmc.js bin/hxmc/boot/hxmc.hxb.zip $(HOST_RT)
	ulimit -s unlimited 2>/dev/null || true; \
	HXMC_GC_DEFAULTS=0 HXMC_JOBS=1 HXMC_STATS=1 HXMC_RT_OBJ=$(CURDIR)/$(HOST_RT) \
	$(NODE) --stack-size=65500 --max-old-space-size=8192 bin/hxmc/boot/hxmc.js $@ \
		--hxb-lib bin/hxmc/boot/hxmc.hxb.zip -main hxmc.Main --custom-target hxmc -D disable-parallelism > $@.log 2>&1 || { cat $@.log; exit 1; }
	ls -l $@

fixpoint: $(TOOL)
	@mkdir -p bin/hxmc/fix
	ulimit -s unlimited 2>/dev/null || true; \
	HXMC_RT_OBJ=$(CURDIR)/$(HOST_RT) $(TOOL) bin/hxmc/fix/a $(TOOL_ARGS) > bin/hxmc/fix/a.log 2>&1 || { cat bin/hxmc/fix/a.log; exit 1; }; \
	HXMC_RT_OBJ=$(CURDIR)/$(HOST_RT) bin/hxmc/fix/a bin/hxmc/fix/b $(TOOL_ARGS) > bin/hxmc/fix/b.log 2>&1 || { cat bin/hxmc/fix/b.log; exit 1; }
	cmp bin/hxmc/fix/a bin/hxmc/fix/b && echo "fixpoint: the tool rebuilt by itself is byte-identical"
	rm -rf bin/hxmc/fix

# --- The port ---

port dev: $(PORT_BIN)
$(PORT_BIN): $(TOOL) $(PORT_SRC) $(STD) $(HOST_RT)
	$(call hxmc,$@,$(PORT_ARGS))

# the release binaries: cross-built from Linux, with mbedtls and libuv (ssl.o, uv.o)
release: $(RELEASE_BIN)
bin/release/%/haxe-in-haxe: $(TOOL) $(PORT_SRC) $(STD) bin/hxmc/rt/%/rt.o
	$(call hxmc,$@,$(PORT_ARGS) -D hxmc.target=$*)
bin/release/%/haxe-in-haxe.exe: $(TOOL) $(PORT_SRC) $(STD) bin/hxmc/rt/%/rt.o
	$(call hxmc,$@,$(PORT_ARGS) -D hxmc.target=$*)

# the playground's compiler: a wasm32-wasi module (its runtime is Haxe, no
# runtime object), without the target generators
wasm: bin/wasm/hih.wasm
bin/wasm/hih.wasm: $(TOOL) $(PORT_SRC) $(STD)
	$(call hxmc,$@,$(PORT_ARGS) -D hih_no_generators -D hxmc.target=wasm32-wasi)

# --- The website ---

# the pages, their scripts (site/src, site/build.hxml), the std subset the
# playground's compiler reads (site/tools/mkbundle.py), the benchmark results
# (site/bench/README.md) and the build facts
mb = awk '{printf "%.1f MB", $$1 / 1048576}'
site: wasm $(SITE_SRC)
	mkdir -p bin/site
	cp bin/wasm/hih.wasm site/index.html site/story.html site/style.css bin/site/
	$(SITE_HAXE) site/build.hxml
	python3 site/tools/mkbundle.py $(HAXE_STD_PATH) bin/site/std.bundle
	cp site/bench/results.json bin/site/bench.json
	cp site/bench/haxebench.json bin/site/programs.json
	cp site/bench/targets-results.json bin/site/targets.json
	rm -rf bin/site/examples && cp -r site/examples bin/site/examples
	rm -rf bin/site/tools
	if [ -n "$(LIX_DIR)" ]; then mkdir -p bin/site/tools && cp $(LIX_DIR)/lix-* bin/site/tools/; fi
	printf '{\n\t"date": "%s",\n\t"commit": "%s",\n\t"wasmSize": "%s",\n\t"wasmGz": "%s",\n\t"dataGz": "%s",\n\t"lixSize": "%s"\n}\n' \
		"$$(date -u +%Y-%m-%d)" "$$(git rev-parse --short HEAD)" \
		"$$(stat -c %s bin/site/hih.wasm | $(mb))" \
		"$$(gzip -9c bin/site/hih.wasm | wc -c | $(mb))" \
		"$$(gzip -9c bin/site/std.bundle | wc -c | $(mb))" \
		"$$(if [ -f bin/site/tools/lix-linux-x86_64 ]; then stat -c %s bin/site/tools/lix-linux-x86_64 | $(mb); else echo -; fi)" > bin/site/build-info.json
	cat bin/site/build-info.json

# --- Other programs ---

fuzz: bin/fuzz/fuzz
bin/fuzz/fuzz: $(TOOL) $(FUZZ_SRC) $(STD) $(HOST_RT)
	$(call hxmc,$@,-cp test/fuzz -main Fuzz $(HXMC_ARGS))

# --- lix (tools/lix/README.md) ---

HXCORO_REV := 4b1a4d49542c578dc184297b75d125093ca444d2
$(HXCORO)/.rev:
	rm -rf $(HXCORO) && git init -q $(HXCORO)
	git -C $(HXCORO) fetch -q --depth 1 https://github.com/HaxeFoundation/hxcoro.git $(HXCORO_REV)
	git -C $(HXCORO) checkout -q FETCH_HEAD
	echo $(HXCORO_REV) > $@

# Mozilla's CA certificates (curl's extract), trusted besides the system's
# (Windows' preinstalled roots lack common ones), as a generated module
CACERT := cacert-2026-09-25.pem
CACERT_SHA256 := a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505
bin/lix/gen/shim/CaBundle.hx: tools/lix/cabundle.py
	@mkdir -p bin/lix
	curl -sSfL --retry 3 -o bin/lix/$(CACERT) https://curl.se/ca/$(CACERT)
	python3 tools/lix/cabundle.py bin/lix/$(CACERT) $(CACERT_SHA256) bin/lix/gen

LIX_ARGS := -cp tools/lix/src -cp bin/lix/gen -cp $(HXCORO)/src -main lix.cli.Main -D no-deprecation-warnings $(HXMC_ARGS)
LIX_DEPS := $(TOOL) $(LIX_SRC) $(STD) $(HXCORO)/.rev bin/lix/gen/shim/CaBundle.hx
lix: bin/lix/lix
bin/lix/lix: $(LIX_DEPS) $(HOST_RT)
	$(call hxmc,$@,$(LIX_ARGS))
	for cmd in haxe haxelib neko; do ln -sf lix bin/lix/$$cmd; done

lix-release: $(LIX_BIN)
bin/release/%/lix: $(LIX_DEPS) bin/hxmc/rt/%/rt.o
	$(call hxmc,$@,$(LIX_ARGS) -D hxmc.target=$*)
bin/release/%/lix.exe: $(LIX_DEPS) bin/hxmc/rt/%/rt.o
	$(call hxmc,$@,$(LIX_ARGS) -D hxmc.target=$*)

# --- Tests (test/README.md has the other harnesses) ---

test: $(PORT_BIN)
	HAXE_REFERENCE=$(CURDIR)/haxe/haxe HAXE_IN_HAXE_PORT=$(abspath $(PORT_BIN)) \
		python3 test/conformance.py -j $(JOBS)

test-fuzz: bin/fuzz/fuzz $(PORT_BIN)
	HAXE_REFERENCE=$(CURDIR)/haxe/haxe bin/fuzz/fuzz -j $(JOBS) -n $(N) --port $(abspath $(PORT_BIN)) --lane $(LANE)

smoke:
	SMOKE_STRICT=$(SMOKE_STRICT) sh tools/smoke.sh $(SMOKE_BIN)

hxmc-test: $(TOOL) $(STD) $(HOST_RT)
	python3 hxmc/tools/run.py -v $(RUN_ARGS)

portcheck: $(TOOL) $(STD) $(HOST_RT)
	sh hxmc/tools/portcheck.sh

quick: $(TOOL) $(STD) $(HOST_RT)
	python3 hxmc/tools/tiers.py quick $(CASES)

check: $(TOOL) $(STD) $(HOST_RT)
	python3 hxmc/tools/tiers.py check $(if $(PORT),--port) $(CASES)

full: $(TOOL) $(STD) $(HOST_RT)
	python3 hxmc/tools/tiers.py full $(CASES)

clean:
	rm -rf bin/port bin/release bin/site bin/wasm bin/fuzz bin/lix bin/hxmc/boot bin/hxmc/fix bin/hxmc-t bin/hxmc-fuzz

distclean:
	rm -rf bin
