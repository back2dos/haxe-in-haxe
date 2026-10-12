package haxeshim.sys;

// port: haxe.DynamicAccess<String> in upstream (node's process.env objects)
typedef Vars = Map<String, String>;

abstract Env(Null<Vars>) {

  @:from static function ofObj(o:Dynamic<String>):Env {
    var ret = new Vars();
    for (k in Reflect.fields(o))
      ret[normalize(k)] = Reflect.field(o, k);
    return new Env(ret);
  }

  @:from static function ofMap(map:Map<String, String>):Env {
    var ret = new Vars();
    for (k in map.keys())
      ret[normalize(k)] = map[k];
    return new Env(ret);
  }

  public function keys():Iterator<String>
    return
      if (this == null) [].iterator()
      else this.keys();

  function vars() return this;

  @:to public function toVars():Vars
    return if (this == null) new Vars() else this.copy();

  inline function new(vars)
    this = vars;

  @:arrayAccess public function get(s:String):Null<String>
    return if (this == null) null else this[normalize(s)];

  static inline function normalize(s:String)
    return if (Os.IS_WINDOWS) s.toUpperCase() else s;

  public function mergeInto(that:Env):Env
    return switch [this, that.vars()] {
      case [null, v] | [v, null]: new Env(v);
      case [a, b]:
        var ret = new Vars();

        for (vars in [b, a])
        for (k in vars.keys())
            ret[k] = vars[k];

        return new Env(ret);
    }

}
