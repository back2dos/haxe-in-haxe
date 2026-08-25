# Upstream parser remainder

The parser corpus intentionally attempts all 1,366 upstream unit sources. The
27 current rejects are diagnostics, not accepted compiler-test exclusions:

| Category | Sources | Priority for first HXB milestone |
| --- | --- | --- |
| Macro quotation/type-definition syntax | `RunCastGenerator`, `TestDefaultTypeParameters`, `TestIssues`, `TestMacro`, issues `2244`, `2634`, `3205`, `3921`, `5162`, `6063`, `7600`, `8859`, `9405`, `9565`, and the nine rejected `issues/misc/*Macro` modules | Later macro milestone |
| Nested interpolation edge cases | issues `6369`, `9370` | Parser follow-up; not a current smoke blocker |
| Inline preprocessor/runtime expression | `TestEReg` | Target/runtime test, not HXB-only conformance |
| Inline XML | `teststd/TestInlineXml` | Target-specific syntax, outside first HXB milestone |

Keep increasing the parser score when changes are mechanical, but do not trade
typed-AST, matcher, or exact HXB parity for a macro-only coverage number.
