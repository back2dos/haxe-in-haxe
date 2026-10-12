package lix.cli;

import haxeshim.scope.Scope;

class HaxeCmd {
  static public function ensureScope()
    if (!Scope.exists(Scope.DEFAULT_ROOT))
      Scope.create(Scope.DEFAULT_ROOT, {
        version: 'stable',
        resolveLibs: Mixed,
      });

  static public function ensure(logger) {
    ensureScope();

    var scope = Scope.seek();
    var hx = new lix.client.haxe.Switcher(scope, logger);

    if (!hx.scope.haxeInstallation.path.exists()) {
      var version = hx.scope.config.version;
      logger.info('Version $version configured in ${hx.scope.configFile} does not exist. Attempting download ...');
      hx.install(version, { force: false });
    }
    // switch scope.getInstallationInstructions().instructions.install.length {
    //   case 0:
    //   case v:
    //     println('Missing $v libraries. Attempting download ...');
    //     new HaxeCli(scope).installLibs(true);
    // }
  }

  static public function main(?args:Array<String>)
    HaxeCli.withArgs(args -> {
      Command.attempt(() -> ensure(Logger.get()));
      HaxeCli.run(args);
    }, args);
}
