# Upstream HXB smoke exclusions

These are discoveries from the source-only smoke inventory, not a complete
upstream-suite manifest. Revisit an entry only when its stated milestone or
missing compiler behavior is implemented.

| Case | Reason |
| --- | --- |
| optimization `Issue5855` | Reference rejects the cross/HXB invocation because it accesses the JS API. |
| eval `Issue3975`, `Issue9017`, `Issue10504`, `Issue12050`, `Issue10707`, `Issue4954`, `Issue6005`, `Issue7559`, `Issue9612` | Reference rejects the tested HXB invocation; these are expected-error or configuration-specific cases. |
| eval `Issue10150`, `Issue10793`, `Issue11004`, `Issue11087`, `Issue11120`, `Issue11128`, `Issue11373`, `Issue11481`, `Issue11538`, `Issue11582`, `Issue11625`, `Issue11670`, `Issue11682`, `Issue11740`, `Issue12430`, `Issue3864`, `Issue4454`, `Issue4790`, `Issue4825`, `Issue5145`, `Issue5456`, `Issue6006`, `Issue6402`, `Issue6583` | The project executes or depends on macros in its intended configuration; excluded until the Eval macro milestone. |
| eval `Issue4456` | Iteration through the `Map` typedef/abstract chain reaches an unselected iterator type parameter during HXB serialization. |
| eval `Issue5122` | Inline local-function lowering is not implemented; parsing it as an ordinary local function would produce non-conforming typed HXB. |
