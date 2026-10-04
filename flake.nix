{
  description = "Star CLI consuming the generated StarLang document contract";
  inputs = {
    star-router.url = "github:lost-rob0t/starRouter/20e5c9e8bf49660fd230d8e7306dd9209648f6e9";
    nixpkgs.follows = "star-router/nixpkgs";
    starintel-doc.follows = "star-router/starintel-doc";
    mycouch = { url = "github:hamidb80/mycouch/8e1b740c623c21e4b180f2d139fa07e6d6a1eff6"; flake = false; };
    macroutils = { url = "github:PMunch/macroutils/b460c6804c97df8cfdc80c308b574ae90b30ac61"; flake = false; };
    macroplus = { url = "github:hamidb80/macroplus/ab49b1b2bfd92fbf69b39ddb3096472d72aaf815"; flake = false; };
  };
  outputs = { self, nixpkgs, star-router, starintel-doc, mycouch, macroutils, macroplus }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      paths = "--noNimblePath --path:src --path:${starintel-doc}/src --path:${star-router}/src --path:${mycouch}/src --path:${macroutils}/src --path:${macroplus}/src --path:${star-router.inputs.cligen} --path:${star-router.inputs.zmq} --path:${star-router.inputs.ulid}/src --path:${star-router.inputs.random}/src";
      libraries = pkgs.lib.makeLibraryPath [ pkgs.pcre pkgs.zeromq ];
      cli = pkgs.stdenv.mkDerivation {
        pname = "star-cli";
        version = "0.1.0";
        src = self;
        nativeBuildInputs = [ pkgs.nim pkgs.python3 pkgs.makeWrapper ];
        buildPhase = ''
          nim c -d:release ${paths} --nimcache:"$TMPDIR/nimcache" --out:star src/star.nim
          nim check ${paths} src/starpkg/router.nim
        '';
        doCheck = true;
        doInstallCheck = true;
        checkPhase = ''
          python3 scripts/sync-starintel-schema.py --offline
          python3 scripts/check-runtime-release.py ${starintel-doc} ${star-router}
          export LD_LIBRARY_PATH=${libraries}
          python3 tests/cli_wire.py "$PWD/star"
        '';
        installPhase = ''
          mkdir -p "$out/bin"
          install -m755 star "$out/bin/star"
          wrapProgram "$out/bin/star" --prefix LD_LIBRARY_PATH : ${libraries}
        '';
        installCheckPhase = ''
          python3 tests/cli_wire.py "$out/bin/star"
        '';
      };
    in {
      packages.${system}.default = cli;
      checks.${system}.default = cli;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nim pkgs.nimble pkgs.python3 ];
        LD_LIBRARY_PATH = libraries;
      };
    };
}
