package lix.client;

// port: tink's Option<String> fields are nullable strings
@:structInit class LibVersion {

  public var name(default, null):Null<String>;
  public var version(default, null):Null<String>;

  function or(a:Null<String>, b:Null<String>)
    return switch a {
      case null: b;
      default: a;
    }

  public function toString()
    return switch name {
      case null: '';
      case v:
        v + switch version {
          case null: '';
          case v: '#$v';
        }
    }

  public function merge(as:LibVersion):LibVersion {
    if (as == null) return this;
    return {
      name: or(as.name, this.name),
      version: or(as.version, this.version),
    }
  }

  static public function parse(s:String):LibVersion
    return
      if (s == null) null;
      else switch s.indexOf('#') {
        case -1:
          { name: s, version: null };
        case v:
          { name: s.substring(0, v), version: s.substring(v + 1) };
      }
  static public var UNDEFINED(default, null):LibVersion = { name: null, version: null };
}
