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

<!-- discovered -->

## Discovered configurations excluded from conformance

| Configuration | Reason |
| --- | --- |
| `eval-GlobalMetadataWildcard-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-HxbWildcardExclude-compile` compile.hxml | multi-part (--next/--each) configuration |
| `eval-Issue10005`  | only compile-fail configurations |
| `eval-Issue10024`  | only compile-fail configurations |
| `eval-Issue10034`  | only compile-fail configurations |
| `eval-Issue10039`  | only compile-fail configurations |
| `eval-Issue10052`  | only compile-fail configurations |
| `eval-Issue10139`  | only compile-fail configurations |
| `eval-Issue10147`  | only compile-fail configurations |
| `eval-Issue10150-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue10170`  | only compile-fail configurations |
| `eval-Issue10171`  | only compile-fail configurations |
| `eval-Issue10184`  | only compile-fail configurations |
| `eval-Issue10186`  | only compile-fail configurations |
| `eval-Issue10189`  | only compile-fail configurations |
| `eval-Issue10219`  | only compile-fail configurations |
| `eval-Issue10229`  | only compile-fail configurations |
| `eval-Issue10245`  | only compile-fail configurations |
| `eval-Issue10264`  | only compile-fail configurations |
| `eval-Issue10287`  | only compile-fail configurations |
| `eval-Issue10291`  | only compile-fail configurations |
| `eval-Issue10325`  | only compile-fail configurations |
| `eval-Issue10358`  | only compile-fail configurations |
| `eval-Issue10426`  | only compile-fail configurations |
| `eval-Issue10482`  | only compile-fail configurations |
| `eval-Issue10504`  | only compile-fail configurations |
| `eval-Issue10521`  | only compile-fail configurations |
| `eval-Issue10587`  | only compile-fail configurations |
| `eval-Issue10591-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue10623`  | only compile-fail configurations |
| `eval-Issue10634`  | only compile-fail configurations |
| `eval-Issue10687`  | only compile-fail configurations |
| `eval-Issue10707`  | only compile-fail configurations |
| `eval-Issue10711-compile` compile.hxml | requires a haxelib library |
| `eval-Issue10729`  | only compile-fail configurations |
| `eval-Issue10793-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue10804`  | only compile-fail configurations |
| `eval-Issue10825`  | only compile-fail configurations |
| `eval-Issue10844`  | only compile-fail configurations |
| `eval-Issue10845`  | only compile-fail configurations |
| `eval-Issue10847`  | only compile-fail configurations |
| `eval-Issue10852`  | only compile-fail configurations |
| `eval-Issue10865`  | only compile-fail configurations |
| `eval-Issue10871`  | only compile-fail configurations |
| `eval-Issue10880`  | only compile-fail configurations |
| `eval-Issue10881`  | only compile-fail configurations |
| `eval-Issue10883`  | only compile-fail configurations |
| `eval-Issue10890`  | only compile-fail configurations |
| `eval-Issue10897`  | only compile-fail configurations |
| `eval-Issue10935`  | only compile-fail configurations |
| `eval-Issue10959`  | only compile-fail configurations |
| `eval-Issue10961`  | only compile-fail configurations |
| `eval-Issue11004`  | only compile-fail configurations |
| `eval-Issue11020`  | only compile-fail configurations |
| `eval-Issue11055`  | only compile-fail configurations |
| `eval-Issue11087-compile-interp` compile-interp.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11087-compile-x` compile-x.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11087-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11120-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11121`  | only compile-fail configurations |
| `eval-Issue11128-compile1` compile1.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11128-compile2` compile2.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11128-compile3` compile3.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11128-compile4` compile4.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11128-compile5` compile5.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11162`  | only compile-fail configurations |
| `eval-Issue11193-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11208`  | only compile-fail configurations |
| `eval-Issue11231`  | only compile-fail configurations |
| `eval-Issue11237`  | only compile-fail configurations |
| `eval-Issue11280`  | only compile-fail configurations |
| `eval-Issue11323-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11334`  | only compile-fail configurations |
| `eval-Issue11342`  | only compile-fail configurations |
| `eval-Issue11354-compile` compile.hxml | multi-part (--next/--each) configuration |
| `eval-Issue11366`  | only compile-fail configurations |
| `eval-Issue11368`  | only compile-fail configurations |
| `eval-Issue11373-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11389`  | only compile-fail configurations |
| `eval-Issue11396`  | only compile-fail configurations |
| `eval-Issue11431`  | only compile-fail configurations |
| `eval-Issue11439`  | only compile-fail configurations |
| `eval-Issue11450`  | only compile-fail configurations |
| `eval-Issue11481-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11528`  | only compile-fail configurations |
| `eval-Issue11538-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11545-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11571`  | only compile-fail configurations |
| `eval-Issue11580`  | only compile-fail configurations |
| `eval-Issue11582-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11595`  | only compile-fail configurations |
| `eval-Issue11625-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11631-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11635`  | only compile-fail configurations |
| `eval-Issue11670-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11679`  | only compile-fail configurations |
| `eval-Issue11682-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11684`  | only compile-fail configurations |
| `eval-Issue11688`  | only compile-fail configurations |
| `eval-Issue11700`  | only compile-fail configurations |
| `eval-Issue11725`  | only compile-fail configurations |
| `eval-Issue11740-compile1` compile1.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11740-compile2` compile2.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11776`  | only compile-fail configurations |
| `eval-Issue11832`  | only compile-fail configurations |
| `eval-Issue11852-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue11870`  | only compile-fail configurations |
| `eval-Issue11881`  | only compile-fail configurations |
| `eval-Issue11913`  | only compile-fail configurations |
| `eval-Issue12050`  | only compile-fail configurations |
| `eval-Issue12098`  | only compile-fail configurations |
| `eval-Issue12131`  | only compile-fail configurations |
| `eval-Issue12167`  | only compile-fail configurations |
| `eval-Issue12171-compile` compile.hxml | reference writes no HXB archive for this configuration |
| `eval-Issue12177-compile` compile.hxml | reference writes no HXB archive for this configuration |
| `eval-Issue12182`  | only compile-fail configurations |
| `eval-Issue12208-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue12355`  | only compile-fail configurations |
| `eval-Issue12430`  | only compile-fail configurations |
| `eval-Issue12483`  | only compile-fail configurations |
| `eval-Issue12526`  | only compile-fail configurations |
| `eval-Issue12873-compile-0-setup` compile-0-setup.hxml | multi-part (--next/--each) configuration |
| `eval-Issue12873-compile-1` compile-1.hxml | requires a haxelib library |
| `eval-Issue12873-compile-2` compile-2.hxml | requires a haxelib library |
| `eval-Issue12934`  | only compile-fail configurations |
| `eval-Issue12945`  | only compile-fail configurations |
| `eval-Issue12977`  | only compile-fail configurations |
| `eval-Issue1310`  | only compile-fail configurations |
| `eval-Issue1968`  | only compile-fail configurations |
| `eval-Issue2087`  | only compile-fail configurations |
| `eval-Issue2148`  | only compile-fail configurations |
| `eval-Issue2263`  | only compile-fail configurations |
| `eval-Issue2278`  | only compile-fail configurations |
| `eval-Issue2472`  | only compile-fail configurations |
| `eval-Issue2729`  | only compile-fail configurations |
| `eval-Issue2969`  | only compile-fail configurations |
| `eval-Issue2991`  | only compile-fail configurations |
| `eval-Issue2993`  | only compile-fail configurations |
| `eval-Issue2995`  | only compile-fail configurations |
| `eval-Issue2997`  | only compile-fail configurations |
| `eval-Issue3053`  | only compile-fail configurations |
| `eval-Issue3129-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue3188-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue3192`  | only compile-fail configurations |
| `eval-Issue3238`  | only compile-fail configurations |
| `eval-Issue3288`  | only compile-fail configurations |
| `eval-Issue3298`  | only compile-fail configurations |
| `eval-Issue3300`  | only compile-fail configurations |
| `eval-Issue3310`  | only compile-fail configurations |
| `eval-Issue3417`  | only compile-fail configurations |
| `eval-Issue3457`  | only compile-fail configurations |
| `eval-Issue3678`  | only compile-fail configurations |
| `eval-Issue3699`  | only compile-fail configurations |
| `eval-Issue3710`  | only compile-fail configurations |
| `eval-Issue3714`  | only compile-fail configurations |
| `eval-Issue3726`  | only compile-fail configurations |
| `eval-Issue3756`  | only compile-fail configurations |
| `eval-Issue3781`  | only compile-fail configurations |
| `eval-Issue3782`  | only compile-fail configurations |
| `eval-Issue3783`  | only compile-fail configurations |
| `eval-Issue3802`  | only compile-fail configurations |
| `eval-Issue3830`  | only compile-fail configurations |
| `eval-Issue3864-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue3907`  | only compile-fail configurations |
| `eval-Issue3931`  | only compile-fail configurations |
| `eval-Issue3975`  | only compile-fail configurations |
| `eval-Issue4070`  | only compile-fail configurations |
| `eval-Issue4114`  | only compile-fail configurations |
| `eval-Issue4160-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue4247`  | only compile-fail configurations |
| `eval-Issue4250`  | only compile-fail configurations |
| `eval-Issue4270`  | only compile-fail configurations |
| `eval-Issue4293`  | only compile-fail configurations |
| `eval-Issue4327`  | only compile-fail configurations |
| `eval-Issue4370`  | only compile-fail configurations |
| `eval-Issue4378`  | only compile-fail configurations |
| `eval-Issue4448`  | only compile-fail configurations |
| `eval-Issue4454-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue4466`  | only compile-fail configurations |
| `eval-Issue4580`  | only compile-fail configurations |
| `eval-Issue4651`  | only compile-fail configurations |
| `eval-Issue4662`  | only compile-fail configurations |
| `eval-Issue4671`  | only compile-fail configurations |
| `eval-Issue4689`  | only compile-fail configurations |
| `eval-Issue4754`  | only compile-fail configurations |
| `eval-Issue4761`  | only compile-fail configurations |
| `eval-Issue4764`  | only compile-fail configurations |
| `eval-Issue4766`  | only compile-fail configurations |
| `eval-Issue4775`  | only compile-fail configurations |
| `eval-Issue4781`  | only compile-fail configurations |
| `eval-Issue4790`  | only compile-fail configurations |
| `eval-Issue4816`  | only compile-fail configurations |
| `eval-Issue4825-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue4891`  | only compile-fail configurations |
| `eval-Issue4904`  | only compile-fail configurations |
| `eval-Issue4907`  | only compile-fail configurations |
| `eval-Issue4954`  | only compile-fail configurations |
| `eval-Issue4957`  | only compile-fail configurations |
| `eval-Issue4982`  | only compile-fail configurations |
| `eval-Issue5008`  | only compile-fail configurations |
| `eval-Issue5010`  | only compile-fail configurations |
| `eval-Issue5039`  | only compile-fail configurations |
| `eval-Issue5118`  | only compile-fail configurations |
| `eval-Issue5122`  | only compile-fail configurations |
| `eval-Issue5123`  | only compile-fail configurations |
| `eval-Issue5125`  | only compile-fail configurations |
| `eval-Issue5128`  | only compile-fail configurations |
| `eval-Issue5134`  | only compile-fail configurations |
| `eval-Issue5145-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue5152`  | only compile-fail configurations |
| `eval-Issue5205`  | only compile-fail configurations |
| `eval-Issue5206`  | only compile-fail configurations |
| `eval-Issue5268`  | only compile-fail configurations |
| `eval-Issue5375`  | only compile-fail configurations |
| `eval-Issue5456-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue5871`  | only compile-fail configurations |
| `eval-Issue5880-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue5924`  | only compile-fail configurations |
| `eval-Issue5940`  | only compile-fail configurations |
| `eval-Issue5946`  | only compile-fail configurations |
| `eval-Issue5949`  | only compile-fail configurations |
| `eval-Issue5952`  | only compile-fail configurations |
| `eval-Issue6005`  | only compile-fail configurations |
| `eval-Issue6006-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue6201`  | only compile-fail configurations |
| `eval-Issue6321-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue6340`  | only compile-fail configurations |
| `eval-Issue6402-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue6435`  | only compile-fail configurations |
| `eval-Issue6443-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue6445`  | only compile-fail configurations |
| `eval-Issue6525`  | only compile-fail configurations |
| `eval-Issue6542`  | only compile-fail configurations |
| `eval-Issue6550`  | only compile-fail configurations |
| `eval-Issue6583-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue6584`  | only compile-fail configurations |
| `eval-Issue6622`  | only compile-fail configurations |
| `eval-Issue6699`  | only compile-fail configurations |
| `eval-Issue6707`  | only compile-fail configurations |
| `eval-Issue6714`  | only compile-fail configurations |
| `eval-Issue6757`  | only compile-fail configurations |
| `eval-Issue6765`  | only compile-fail configurations |
| `eval-Issue6794`  | only compile-fail configurations |
| `eval-Issue6796`  | only compile-fail configurations |
| `eval-Issue6826`  | only compile-fail configurations |
| `eval-Issue6878`  | only compile-fail configurations |
| `eval-Issue6903`  | only compile-fail configurations |
| `eval-Issue6938`  | only compile-fail configurations |
| `eval-Issue6950`  | only compile-fail configurations |
| `eval-Issue6965`  | only compile-fail configurations |
| `eval-Issue7017`  | only compile-fail configurations |
| `eval-Issue7039`  | only compile-fail configurations |
| `eval-Issue7076`  | only compile-fail configurations |
| `eval-Issue7108`  | only compile-fail configurations |
| `eval-Issue7210-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue7227`  | only compile-fail configurations |
| `eval-Issue7333`  | only compile-fail configurations |
| `eval-Issue7363`  | only compile-fail configurations |
| `eval-Issue7526`  | only compile-fail configurations |
| `eval-Issue7559`  | only compile-fail configurations |
| `eval-Issue7614`  | only compile-fail configurations |
| `eval-Issue7638`  | only compile-fail configurations |
| `eval-Issue7669`  | only compile-fail configurations |
| `eval-Issue7747`  | only compile-fail configurations |
| `eval-Issue7752`  | only compile-fail configurations |
| `eval-Issue7780`  | only compile-fail configurations |
| `eval-Issue7809`  | only compile-fail configurations |
| `eval-Issue7824`  | only compile-fail configurations |
| `eval-Issue7855`  | only compile-fail configurations |
| `eval-Issue7871`  | only compile-fail configurations |
| `eval-Issue7905-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue7920`  | only compile-fail configurations |
| `eval-Issue7921`  | only compile-fail configurations |
| `eval-Issue7935`  | only compile-fail configurations |
| `eval-Issue7968`  | only compile-fail configurations |
| `eval-Issue7997`  | only compile-fail configurations |
| `eval-Issue8019`  | only compile-fail configurations |
| `eval-Issue8119`  | only compile-fail configurations |
| `eval-Issue8159-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8173`  | only compile-fail configurations |
| `eval-Issue8191`  | only compile-fail configurations |
| `eval-Issue8202-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8205`  | only compile-fail configurations |
| `eval-Issue8258`  | only compile-fail configurations |
| `eval-Issue8277`  | only compile-fail configurations |
| `eval-Issue8283`  | only compile-fail configurations |
| `eval-Issue8336`  | only compile-fail configurations |
| `eval-Issue8393`  | only compile-fail configurations |
| `eval-Issue8404-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8466-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8471-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8471-compile2-pretty` compile2-pretty.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8471-compile2` compile2.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8488`  | only compile-fail configurations |
| `eval-Issue8517-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8527`  | only compile-fail configurations |
| `eval-Issue8533-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8534`  | only compile-fail configurations |
| `eval-Issue8551`  | only compile-fail configurations |
| `eval-Issue8565`  | only compile-fail configurations |
| `eval-Issue8574`  | only compile-fail configurations |
| `eval-Issue8579`  | only compile-fail configurations |
| `eval-Issue8608`  | only compile-fail configurations |
| `eval-Issue8618`  | only compile-fail configurations |
| `eval-Issue8634`  | only compile-fail configurations |
| `eval-Issue8650`  | only compile-fail configurations |
| `eval-Issue8654-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8677`  | only compile-fail configurations |
| `eval-Issue8689`  | only compile-fail configurations |
| `eval-Issue8697`  | only compile-fail configurations |
| `eval-Issue8704`  | only compile-fail configurations |
| `eval-Issue8705-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8750-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue8752`  | only compile-fail configurations |
| `eval-Issue8765`  | only compile-fail configurations |
| `eval-Issue8787`  | only compile-fail configurations |
| `eval-Issue8790`  | only compile-fail configurations |
| `eval-Issue8819`  | only compile-fail configurations |
| `eval-Issue8840`  | only compile-fail configurations |
| `eval-Issue9010`  | only compile-fail configurations |
| `eval-Issue9014`  | only compile-fail configurations |
| `eval-Issue9015`  | only compile-fail configurations |
| `eval-Issue9017`  | only compile-fail configurations |
| `eval-Issue9061`  | only compile-fail configurations |
| `eval-Issue9067`  | only compile-fail configurations |
| `eval-Issue9163`  | only compile-fail configurations |
| `eval-Issue9171`  | only compile-fail configurations |
| `eval-Issue9226`  | only compile-fail configurations |
| `eval-Issue9243`  | only compile-fail configurations |
| `eval-Issue9245`  | only compile-fail configurations |
| `eval-Issue9286`  | only compile-fail configurations |
| `eval-Issue9294`  | only compile-fail configurations |
| `eval-Issue9295`  | only compile-fail configurations |
| `eval-Issue9336-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9342-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9347`  | only compile-fail configurations |
| `eval-Issue9368`  | only compile-fail configurations |
| `eval-Issue9378`  | only compile-fail configurations |
| `eval-Issue9381-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9389`  | only compile-fail configurations |
| `eval-Issue9390`  | only compile-fail configurations |
| `eval-Issue9391`  | only compile-fail configurations |
| `eval-Issue9417`  | only compile-fail configurations |
| `eval-Issue9425-compile-success` compile-success.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9430`  | only compile-fail configurations |
| `eval-Issue9483-compile-success` compile-success.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9556`  | only compile-fail configurations |
| `eval-Issue9584`  | only compile-fail configurations |
| `eval-Issue9612`  | only compile-fail configurations |
| `eval-Issue9619`  | only compile-fail configurations |
| `eval-Issue9631`  | only compile-fail configurations |
| `eval-Issue9640`  | only compile-fail configurations |
| `eval-Issue9659`  | only compile-fail configurations |
| `eval-Issue9676`  | only compile-fail configurations |
| `eval-Issue9692`  | only compile-fail configurations |
| `eval-Issue9769-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9785`  | only compile-fail configurations |
| `eval-Issue9796`  | only compile-fail configurations |
| `eval-Issue9838-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-Issue9971`  | only compile-fail configurations |
| `eval-Pull11784-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-coro`  | only compile-fail configurations |
| `eval-coro_ctor`  | only compile-fail configurations |
| `eval-ctor_callable_abstract`  | only compile-fail configurations |
| `eval-customExt-compile1` compile1.hxml | creates a macro context (Eval macro milestone) |
| `eval-customExt-compile2` compile2.hxml | creates a macro context (Eval macro milestone) |
| `eval-defaultArgConstructorThis`  | only compile-fail configurations |
| `eval-default_type_params`  | only compile-fail configurations |
| `eval-display-package`  | only compile-fail configurations |
| `eval-display-type`  | only compile-fail configurations |
| `eval-extern-overloads`  | only compile-fail configurations |
| `eval-inline-for`  | only compile-fail configurations |
| `eval-issue5002`  | only compile-fail configurations |
| `eval-local-static`  | only compile-fail configurations |
| `eval-output-flushing`  | only compile-fail configurations |
| `eval-recursive-callbacks-compile` compile.hxml | creates a macro context (Eval macro milestone) |
| `eval-sys-exit-compile00` compile00.hxml | multi-part (--next/--each) configuration |
| `resolution-Issue9189`  | only compile-fail configurations |
| `resolution-Issue9367-compile` compile.hxml | requires a haxelib library |
| `resolution-modulestatics-compile` compile.hxml | requires a haxelib library |
| `resolution-spec-compile` compile.hxml | requires a haxelib library |
| `loops-Issue5189`  | only compile-fail configurations |
| `loops-Issue5345`  | only compile-fail configurations |
| `loops-Issue8588`  | only compile-fail configurations |
| `loops-Issue9397-compile` compile.hxml | reference timed out |
| `loops-Issue9428`  | only compile-fail configurations |
| `optimization-Issue10765` issues.Issue10765 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.DataView) |
| `optimization-Issue10908` issues.Issue10908 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.html.VideoElement) |
| `optimization-Issue5745` issues.Issue5745 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue5855` issues.Issue5855 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue6225` issues.Issue6225 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue6283` issues.Issue6283 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue6338` issues.Issue6338 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue6409` issues.Issue6409 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
| `optimization-Issue7113` issues.Issue7113 | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.Syntax) |
| `optimization-IssueInline` issues.IssueInline | reference rejects the HXB invocation: You cannot access the js package while targeting eval (for js.lib.Error) |
