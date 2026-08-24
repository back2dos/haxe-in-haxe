# Upstream HXB smoke exclusions

These are discoveries from the source-only smoke inventory, not a complete
upstream-suite manifest. Revisit an entry only when its stated milestone or
missing compiler behavior is implemented.

| Case | Reason |
| --- | --- |
| optimization `Issue5855` | Reference rejects the cross/HXB invocation because it accesses the JS API. |
| eval `Issue3975`, `Issue9017`, `Issue10504`, `Issue12050`, `Issue10707`, `Issue4954`, `Issue6005`, `Issue7559`, `Issue9612` | Reference rejects the tested HXB invocation; these are expected-error or configuration-specific cases. |
| eval `Issue11481`, `Issue11740`, `Issue3864` | The effective invocation executes or depends on macros; excluded until the Eval macro milestone. |
| eval `Issue4070` | Port emits HXB, but reference consumption fails on unresolved constrained type parameter `Main.T`. |
| eval `Issue11686` | Port does not yet support this iterator form. |
| eval `Issue11164` | A reachable pinned-stdlib `BalancedTree` syntax form is not parsed yet. |
| eval `Issue10804` | A reachable pinned-stdlib `Vector` class-field syntax form is not parsed yet. |
