package hxmc.esx;

// Implemented by a class whose markup literals are compiled (the build
// macro, MarkupMacro.build): <div>..</div> anywhere in its fields
@:autoBuild(hxmc.esx.MarkupMacro.build())
interface Markup {}
