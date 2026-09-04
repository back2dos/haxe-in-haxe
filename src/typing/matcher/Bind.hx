package typing.matcher;

import core.TType;
import core.Globals.Pos;

// haxe/src/typing/matcher/bind.ml — mechanical draft; not compile-validated.
enum BindStatus { BindUsed; BindUnused; BindDeferred; }
typedef Bind = {var bVar:TVar; var bPos:Pos; var bExpr:TExpr; var bStatus:BindStatus;}
