{ config, pkgs, plugins, ... }:

with pkgs;

stdenv.mkDerivation rec {
  # Disable the Nix build sandbox for this specific build.
  # This means the build can freely talk to the Internet.
  # Requires the sandbox to be set to false/"relaxed".
  __noChroot = true;
  pname = "caddy";
  # https://github.com/NixOS/nixpkgs/issues/113520
  version = "latest";
  dontUnpack = true;

  nativeBuildInputs = [ git go xcaddy ];

  configurePhase = ''
    export GOCACHE=$TMPDIR/go-cache
    export GOPATH="$TMPDIR/go"
  '';

  buildPhase = let
    pluginArgs = lib.concatMapStringsSep " " (plugin: "--with ${plugin}") plugins;
  in ''
    runHook preBuild
    ${xcaddy}/bin/xcaddy build latest ${pluginArgs}
    runHook postBuild
  '';


  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mv caddy $out/bin
    runHook postInstall
  '';
}
