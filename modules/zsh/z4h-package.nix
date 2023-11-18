{ config, lib, pkgs, plugins, ... }:

with pkgs;

stdenv.mkDerivation rec {
  # Disable the Nix build sandbox for this specific build.
  # This means the build can freely talk to the Internet.
  # Requires the sandbox to be set to false/"relaxed".
  __noChroot = true;

  pname = "zsh4humans";
  version = "latest";
  dontUnpack = true;

  nativeBuildInputs = [ zsh curl cacert git ];

  buildPhase = ''
    runHook preBuild
    export HOME=$(pwd)
    export ZDOTDIR=$(pwd)
    export XDG_CACHE_HOME="$(pwd)"/.cache
    echo 'if [ -n "''${ZSH_VERSION-}" ]; then

  : ''${ZDOTDIR:=~}
  setopt no_global_rcs
  [[ -o no_interactive && -z "''${Z4H_BOOTSTRAPPING-}" ]] && return
  setopt no_rcs
  unset Z4H_BOOTSTRAPPING
fi

Z4H_URL="https://raw.githubusercontent.com/romkatv/zsh4humans/v5"
: "''${Z4H:=''${XDG_CACHE_HOME:-''$HOME/.cache}/zsh4humans/v5}"

umask o-w

if [ ! -e "''$Z4H"/z4h.zsh ]; then
  mkdir -p "''$Z4H"
  curl -fsSL -- "''$Z4H_URL"/z4h.zsh >"''$Z4H"/z4h.zsh
fi
. "''$Z4H"/z4h.zsh || return
setopt rcs
' > "$ZDOTDIR"/.zshenv
    echo '
zstyle ':z4h:' auto-update      'no'
${(lib.strings.concatMapStringsSep "\n" (plg: "z4h install " + plg) plugins)}
z4h init
${(lib.strings.concatMapStringsSep "\n" (plg: "z4h load " + plg) plugins)}
' > "''$ZDOTDIR"/.zshrc
    zsh -i -l -c 'exit'
    sh -c 'printf "-z4h-compinit-impl\n"; sleep 1; printf "echo 2\n"' | zsh -l
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    mv .cache/zsh4humans/v5 $out/share/z4h
    runHook postInstall
  '';
}
