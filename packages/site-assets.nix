{ lib, pkgs, stdenvNoCC, primary, secondary }:

# TODO: Investigate using <https://github.com/jtippet/IcoTools> for
# smaller .ico files. See: <https://github.com/oxipng/oxipng/issues/440>.

let
  primary-standin = "#e66100";
  secondary-standin = "#1c71d8";
  theme-envs = lib.concatStringsSep " " [
    "PRIMARY_STANDIN='${primary-standin}'"
    "SECONDARY_STANDIN='${secondary-standin}'"
    "PRIMARY_COLOR='${primary}'"
    "SECONDARY_COLOR='${secondary}'"
  ];
in stdenvNoCC.mkDerivation rec {
  name = "site-assets";
  version = "1.0";

  src = ../assets;

  nativeBuildInputs = with pkgs; [ bash gnused svgo librsvg libwebp pngquant oxipng python313Packages.pillow ];

  buildPhase = "${theme-envs} bash build.sh";

  installPhase = ''
  rm build.sh
  mkdir -p $out
  cp -r . $out
  '';
}
