# hxmc, the machine-code target (hxmc/README.md). GNU make, run from the
# repository root:
#
#   make -f hxmc/Makefile              bin/hxmc/hxmc: the tool, built by itself
#   make -f hxmc/Makefile bootstrap    the first tool, from the reference compiler (and node)
#   make -f hxmc/Makefile fixpoint     the tool rebuilt twice must not change
#   make -f hxmc/Makefile test         the corpus against its golden files
#   make -f hxmc/Makefile help         the targets and variables below
#
# Outputs go to bin/ (ignored by Git). Nothing here uses hxc.

# --- Variables (override on the command line) ---

# the reference compiler: writes the HXB of test programs and the bootstrap's JS
HAXE ?= haxe/haxe
export HAXE_STD_PATH ?= $(CURDIR)/haxe/std
# the bootstrap runs the tool as JavaScript: node and hxnodejs (without haxelib,
# e.g. in CI: TOOL_LIBS="<clone>/extraParams.hxml -cp <clone>/src")
NODE ?= node
TOOL_LIBS ?= -lib hxnodejs
ZIG ?= zig
export ZIG
# the targets whose runtime objects `make -f hxmc/Makefile rt` builds
RT_TARGETS ?= linux-x86_64 linux-arm64 windows-x86_64 windows-arm64 macos-x86_64 macos-arm64
# the machine the tool runs on (its own runtime object)
HOST ?= linux-x86_64
# `test`: extra arguments of hxmc/tools/run.py (e.g. RUN_ARGS="--target linux-arm64")
RUN_ARGS ?=

# --- Sources ---

PORT_SRC := $(shell find src -name '*.hx')
HXMC_SRC := $(shell find hxmc/src -name '*.hx')
STD_SRC := $(shell find hxmc/std -type f)
RT_SRC := $(wildcard hxmc/rt/*.c hxmc/rt/*.h)
BOOT_SRC := $(shell find hxmc/tools/bootstrap/js -name '*.hx')

STD := bin/hxmc/std/.stamp
HOST_RT := bin/hxmc/rt/$(HOST)/rt.o
TOOL := bin/hxmc/hxmc
# the tool is the port (src) with hxmc (hxmc/src) as its generate hook, typed
# against hxmc's std
TOOL_CP := -cp src -cp hxmc/src -main hxmc.Main -D disable-parallelism -D hih_no_generators -cp bin/hxmc/std
TOOL_ARGS := $(TOOL_CP) --custom-target hxmc

.DEFAULT_GOAL := tool
.PHONY: help std rt tool bootstrap fixpoint test portcheck clean

help:
	@sed -n '/^# --- Targets/,$$p' $(MAKEFILE_LIST) | sed -n 's/^## \{0,1\}//p'

# --- Targets ---
## std        bin/hxmc/std: hxmc/std merged with the Eval originals (hxmc/tools/mkstd.py)
## rt         the runtime objects of RT_TARGETS (bin/hxmc/rt/<target>/rt.o, zig cc)
## tool       bin/hxmc/hxmc: the tool, built by the previous tool from source
##            (no tool yet: the bootstrap first)
## bootstrap  the tool from scratch: the reference compiler writes the tool's
##            JavaScript and its HXB, node runs the JavaScript to compile the
##            HXB to bin/hxmc/boot/hxmc1, which then builds bin/hxmc/hxmc
## fixpoint   bin/hxmc/hxmc builds bin/hxmc/fix/a, which builds bin/hxmc/fix/b:
##            a and b must be byte-identical
## test       hxmc/tools/run.py: the corpus against hxmc/test/expected (RUN_ARGS)
## portcheck  hxmc/tools/portcheck.sh: the port built by hxmc self-compiles to the reference's HXB
## clean      remove bin/hxmc*
##
## Variables: HAXE, HAXE_STD_PATH, NODE, TOOL_LIBS, ZIG, RT_TARGETS, HOST, RUN_ARGS

std: $(STD)
$(STD): hxmc/tools/mkstd.py $(STD_SRC)
	python3 hxmc/tools/mkstd.py

# the host's runtime object needs no hxmc (Linux: zig cc and ld.lld); the
# Windows and macOS ones are assembled by the tool (hxmc --mkrt)
$(HOST_RT): hxmc/tools/mkrt.sh $(RT_SRC)
	sh hxmc/tools/mkrt.sh $(HOST)

rt: $(TOOL) $(HOST_RT)
	for t in $(RT_TARGETS); do sh hxmc/tools/mkrt.sh $$t || exit 1; done

# The tool compiles its own source with the previous tool (written next to it,
# then moved: the running binary is replaced). A change to code generation
# reaches the tool's own code on the next rebuild (`fixpoint` checks that a
# rebuild changes nothing).
tool: $(TOOL)
$(TOOL): $(PORT_SRC) $(HXMC_SRC) $(STD) $(HOST_RT)
	@if [ ! -x $@ ]; then $(MAKE) -f hxmc/Makefile bin/hxmc/boot/hxmc1; fi
	@T=$@; [ -x $$T ] || T=bin/hxmc/boot/hxmc1; \
	echo "$$T $@.new $(TOOL_ARGS)"; \
	ulimit -s unlimited 2>/dev/null || true; \
	HXMC_RT_OBJ=$(CURDIR)/$(HOST_RT) $$T $@.new $(TOOL_ARGS) > bin/hxmc/tool.log 2>&1 || { cat bin/hxmc/tool.log; exit 1; }
	mv $@.new $@
	ls -l $@

bootstrap:
	rm -f $(TOOL) bin/hxmc/boot/hxmc1
	$(MAKE) -f hxmc/Makefile $(TOOL)

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

test: $(TOOL) $(STD) $(HOST_RT)
	python3 hxmc/tools/run.py -v $(RUN_ARGS)

portcheck: $(TOOL) $(STD) $(HOST_RT)
	sh hxmc/tools/portcheck.sh

clean:
	rm -rf bin/hxmc bin/hxmc-t bin/hxmc-fuzz
