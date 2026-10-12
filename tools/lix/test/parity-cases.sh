# The cases of tools/lix/test/parity.sh: run_case <name> <shell command>...
# Each case starts from an empty root (HAXESHIM_ROOT) and project directory,
# sharing one download of Haxe 4.3.6 and neko (prepare_haxe).

prepare_haxe

run_case help 'lix' 'lix help' 'lix --version' 'lix -v extra' 'lix nope'
run_case scope 'lix scope' 'lix scope create' 'cat .haxerc' 'lix scope' 'lix scope delete' 'lix scope' 'lix scope delete' 'lix scope create extra'
run_case global-install 'lix install haxelib:tink_core'
run_case not-a-url 'lix scope create' 'lix install tink_core'
run_case install-haxelib 'lix scope create' 'lix install haxelib:tink_core' 'lix install haxelib:tink_core'
run_case install-haxelib-version 'lix scope create' 'lix install haxelib:tink_core#1.13.1'
run_case install-plus-lib 'lix scope create' 'lix +lib tink_core#1.13.1'
run_case install-alias 'lix scope create' 'lix install haxelib:tink_core as othername#1.2.3'
run_case install-dependencies 'lix scope create' 'lix install haxelib:tink_json'
run_case install-flat 'lix scope create' 'lix install haxelib:tink_json --flat'
run_case install-force 'lix scope create' 'lix install haxelib:tink_core' 'lix install haxelib:tink_core --force'
run_case install-missing-version 'lix scope create' 'lix install haxelib:tink_core#0.0.42'
run_case install-missing-lib 'lix scope create' 'lix install haxelib:surely_no_such_lib_here'
run_case install-git 'lix scope create' 'lix install git:https://github.com/haxetink/tink_chunk#d48423f6ccd6ba9f0d529c7579138b9aabbbc7bd'
run_case install-zip-url 'lix scope create' 'lix install https://lib.haxe.org/p/hxnodejs/12.2.0/download/'
run_case download 'lix scope create' 'lix use haxe 4.3.6' 'lix install haxelib:tink_json' 'rm -rf ../root/haxe_libraries' 'lix download' 'ls ../root/haxe_libraries'
run_case download-url 'lix scope create' 'lix download haxe' 'lix download nope:x' 'lix download haxelib:tink_core#2.1.1' 'lix download haxelib:tink_core#2.1.1 into custom/place'
run_case dev 'lix scope create' 'mkdir -p mylib/src' 'echo "{\"name\":\"mylib\",\"version\":\"1.0.0\",\"classPath\":\"src\",\"dependencies\":{\"tink_core\":\"\"}}" > mylib/haxelib.json' 'lix dev mylib mylib' 'lix dev nope nope' 'lix dev mylib'
run_case haxe-versions 'lix scope create' 'lix haxe-versions' 'lix haxe-versions extra'
run_case use-haxe 'lix scope create' 'lix use haxe 4.3.6' 'cat .haxerc' 'lix use haxe 9.9.9' 'lix use haxe'
run_case run 'lix scope create' 'mkdir -p haxe_libraries' 'printf "# @run: echo running \${SCOPE_DIR}\n" > haxe_libraries/foo.hxml' 'lix run foo a "b c"' 'lix foo d' 'lix run' 'lix run nope'
run_case resolve 'lix scope create' 'lix use haxe 4.3.6' 'lix install haxelib:tink_json' 'haxe --run resolve-args -lib tink_json' 'haxe --run resolve-args -lib nope' 'haxelib path tink_json' 'haxelib libpath tink_core' 'haxelib path nope'
run_case interpolation 'lix scope create' 'lix use haxe 4.3.6' 'mkdir -p haxe_libraries src' 'printf -- "-cp \${SCOPE_DIR}/src\n-D foo=\${FOO_VAR}\n" > haxe_libraries/foo.hxml' 'FOO_VAR=bar haxe --run resolve-args -lib foo' 'haxe --run resolve-args -lib foo' 'haxe --run resolve-args --cwd src -cp . --next -cp x'

run_case compile 'lix scope create' 'lix use haxe 4.3.6' 'lix install haxelib:tink_core' 'mkdir -p src' 'printf "class Main { static function main() { trace(tink.core.Outcome.Success(1)); trace(Sys.args()); } }\n" > src/Main.hx' 'haxe -cp src -lib tink_core --run Main a b' 'haxe -cp src -lib tink_core -main Main --interp' 'haxe -version' 'haxe --run show-version' 'haxe -cp nope -main Main --interp' 'haxe nope.hxml' 'neko -version'
run_case script 'lix scope create' 'lix use haxe 4.3.6' 'lix install haxelib:tink_core' 'mkdir -p scripts' 'printf "//! -lib tink_core -D greeting=hi\nclass Greet { static function main() { trace(haxe.macro.Compiler.getDefine(\"greeting\") + Sys.args().join(\",\")); } }\n" > scripts/Greet.hx' 'lix Greet a b' 'lix Nope'
run_case install-libs 'lix scope create' 'lix use haxe 4.3.6' 'lix install haxelib:tink_json' 'rm -rf ../root/haxe_libraries' 'haxe --run install-libs' 'haxe --run install-libs extra' 'haxe --run nope-ext'
