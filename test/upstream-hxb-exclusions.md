# Upstream HXB smoke exclusions

These are discoveries from the source-only smoke inventory, not a complete
upstream-suite manifest. Revisit an entry only when its stated milestone or
missing compiler behavior is implemented.

| Case | Reason |
| --- | --- |
| optimization `Issue5855` | Reference rejects the cross/HXB invocation because it accesses the JS API. |
| eval `Issue3975`, `Issue9017`, `Issue10504`, `Issue12050`, `Issue10707`, `Issue4954`, `Issue6005`, `Issue7559`, `Issue9612` | Reference rejects the tested HXB invocation; these are expected-error or configuration-specific cases. |
| eval `Issue10150`, `Issue10793`, `Issue11004`, `Issue11087`, `Issue11120`, `Issue11128`, `Issue11373`, `Issue11481`, `Issue11538`, `Issue11582`, `Issue11625`, `Issue11740`, `Issue3864` | The project executes or depends on macros in its intended configuration; excluded until the Eval macro milestone. |
