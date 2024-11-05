{
  nixpkgs ? import <nixpkgs> {},
  haskell-tools ? import (builtins.fetchTarball "https://github.com/danwdart/haskell-tools/archive/master.tar.gz") {
    nixpkgs = nixpkgs;
    compiler = compiler;
  },
  compiler ? "ghc910"
}:
let
  pkgsForX86 = if builtins.currentSystem == "x86_64-linux" then nixpkgs else nixpkgs.pkgsCross.gnu64.pkgsBuildHost;
  pkgsX86 = if builtins.currentSystem == "x86_64-linux" then nixpkgs else nixpkgs.pkgsCross.gnu64.pkgsHostHost;
  gitignore = nixpkgs.nix-gitignore.gitignoreSourcePure [ ./.gitignore ];
  tools = haskell-tools compiler;
  lib = pkgsX86.haskell.lib;
  myHaskellPackages = pkgsX86.haskell.packages.${compiler}.override {
    overrides = self: super: rec {
      openfaas-examples = lib.dontHaddock (self.callCabal2nix "openfaas-examples" (gitignore ./.) {});
      openfaas = self.callCabal2nix "openfaas" (nixpkgs.fetchFromGitHub {
        owner = "JolHarg";
        repo = "hs-openfaas";
        rev = "0455ae2c55d5f4dfe9832b1e94c714b6933c61a9";
        sha256 = "++y6oEo9RSHE6PB0clgeEdL8QQK0gA4JjrcTdFy2AW4=";
      }) {};
      # Tests for aeson don't work because they should be run as host
      # "Couldn't find a target code interpreter. Try with -fexternal-interpreter"
      aeson = if builtins.currentSystem == "x86_64-linux" then super.aeson else lib.dontCheck super.aeson;
    };
   };
  shell = myHaskellPackages.shellFor {
    packages = p: [
      p.openfaas-examples
    ];
    shellHook = ''
      gen-hie > hie.yaml
      for i in $(find -type f | grep -v dist-newstyle); do krank $i; done
      cabal update

      build() {
          nix-build -A openfaas-examples -o build
          for PACKAGE in packages/*/*/
          do
              rm -rf $PACKAGE/openfaas-examples
              cp build/bin/openfaas-examples $PACKAGE/openfaas-examples
              rm -rf $PACKAGE/*.so*
              cp ${pkgsX86.libffi.outPath}/lib64/libffi.so.8.1.2 $PACKAGE/libffi.so.8
              cp ${pkgsX86.gmp.outPath}/lib/libgmp.so.10.5.0 $PACKAGE/libgmp.so.10
              cp ${pkgsX86.glibc.outPath}/lib/{libc.so.6,libm.so.6,librt.so.1,libdl.so.2,ld-linux-x86-64.so.2} $PACKAGE/
              #x86_64-unknown-linux-gnu-strip $PACKAGE/openfaas-examples
              chmod +w $PACKAGE/*
              patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $PACKAGE/libc.so.6
          done
      }

      clean() {
        git clean -Xf packages
      }

      [[ -f packages/openfaas-examples/debug/libc.so.6 ]] || build

      # wget -c https://raw.githubusercontent.com/oufm/packelf/master/packelf.sh
      # chmod +x packelf.sh
      # export GHC=${if builtins.currentSystem == "aarch64-linux" then "x86_64-unknown-linux-ghc" else "ghc"}
    '';
    buildInputs = tools.defaultBuildTools ++ (with nixpkgs; [
        nodejs_20
        closurecompiler
        pkgsForX86.cabal-install
        pkgsForX86.gcc
        pkgsX86.gmp
        pkgsX86.libffi
        pkgsX86.glibc
    ]);
    nativeBuildInputs = tools.defaultBuildTools ++ (with nixpkgs; [
        nodejs_20
        closurecompiler
        pkgsForX86.cabal-install
        pkgsForX86.gcc
        pkgsX86.gmp
        pkgsX86.libffi
        pkgsX86.glibc
    ]);
    withHoogle = false;
  };
  in
{
  inherit shell;
  openfaas-examples = lib.justStaticExecutables (myHaskellPackages.openfaas-examples);
}
