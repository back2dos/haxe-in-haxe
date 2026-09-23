# Upstream HXB smoke exclusions

These are discoveries from the source-only smoke inventory, not a complete
upstream-suite manifest. Revisit an entry only when its stated milestone or
missing compiler behavior is implemented.

| Case | Reason |
| --- | --- |
| optimization `Issue5855` | Reference rejects the cross/HXB invocation because it accesses the JS API. |
| eval `Issue3975`, `Issue9017`, `Issue10504`, `Issue12050`, `Issue10707`, `Issue4954`, `Issue6005`, `Issue7559`, `Issue9612` | Reference rejects the tested HXB invocation; these are expected-error or configuration-specific cases. |
| eval `Issue2508` | Requires complex pattern-matcher typing; rejecting it is preferable to emitting fields with omitted bodies. |
| eval `Issue2938`, `Issue4456` (direct and HXML), `Issue4720`, `Issue8530`, `Issue10739`, `Issue10804`, `Issue11005`, `Issue11545`, `Issue11676`, `Issue11686`, `Issue12177` | Require abstract-constructor typing and inlining; an unresolved `new Foo(...)` placeholder is not a valid typed result. |
| eval `Issue10150`, `Issue10793`, `Issue11004`, `Issue11087`, `Issue11120`, `Issue11128`, `Issue11373`, `Issue11481`, `Issue11538`, `Issue11582`, `Issue11625`, `Issue11670`, `Issue11682`, `Issue11740`, `Issue12430`, `Issue2729`, `Issue3864`, `Issue4160`, `Issue4454`, `Issue4790`, `Issue4825`, `Issue5145`, `Issue5456`, `Issue5880`, `Issue6006`, `Issue6402`, `Issue6443`, `Issue6583`, `Issue6794`, `Issue7905`, `Issue8159`, `Issue8202`, `Issue8303`, `Issue8404`, `Issue8517`, `Issue8533`, `Issue8705`, `Issue8750`, `Issue9342`, `Issue9381`, `Issue9390`, `Issue9425`, `Issue9483`, `Issue9769`, `Pull11784` | The project executes or depends on macros in its intended configuration; excluded until the Eval macro milestone. |
| eval `Issue11396` | Source uses `[var tmp];` which is not a valid expression statement; reference rejects. |
| eval `Issue12526` | Source uses `??=` assignment to `final` variable; reference rejects. |
| eval `Issue4982` | Source throws result of `Void` function; reference rejects. |
| eval `Issue5854` | Source declares `final` function variables without calling them; reference rejects. |
| eval `callSuper` | Source omits `super.init()` call in override; reference rejects. |
| eval `coro_ctor` | Source uses `@:coroutine` on constructor and calls missing constructor; reference rejects. |
