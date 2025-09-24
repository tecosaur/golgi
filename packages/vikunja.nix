{
  lib,
  pkgs,
  fetchFromGitHub,
  stdenvNoCC,
  stdenv,
  nodejs,
  pnpm_9,
  buildGoModule,
  mage,
  writeShellScriptBin,
  nixosTests,
}:

let
  version = "0.25.0-pre.1";
  src = fetchFromGitHub {
    owner = "go-vikunja";
    repo = "vikunja";
    rev = "4bb483a2d1e27dbd5deea26f77cf8263f5aeb10e";
    hash = "sha256-uR6u3wd+/YXR/xANXLdrvRHIRDoHOK+/1OUcDfq8EhY=";
  };

  frontend = stdenv.mkDerivation (finalAttrs: {
    pname = "vikunja-frontend";
    inherit version src;

    sourceRoot = "${finalAttrs.src.name}/frontend";

    pnpmDeps = pnpm_9.fetchDeps {
      inherit (finalAttrs) pname version src sourceRoot;
      fetcherVersion = 1;
      hash = "sha256-SypmK4A1JhZgueuobdscDCcowHx8aX/LlRqRAO8J+RI=";
    };

    nativeBuildInputs = [
      pkgs.nodejs
      pnpm_9.configHook
    ];

    doCheck = true;

    # Bonus theming
    prePatch = ''
      cp -f ${../assets/vikunja/frontend}/* src/assets
      # Webpage theming
      substituteInPlace src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-h: 217deg" "--primary-h: 146deg"
      substituteInPlace src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-s: 98%" "--primary-s: 56%"
      substituteInPlace src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-l: 53%" "--primary-l: 37%"
      substituteInPlace src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-l: 58%" "--primary-l: 42%"
      # PWA theming
      substituteInPlace vite.config.ts --replace-warn \
        "1973ff" "239a58"
    '';

    postBuild = ''
      find node_modules/.pnpm/sass-embedded-linux-*/node_modules/sass-embedded-linux-*/dart-sass/src -name dart -print0 | xargs -I {} -0 patchelf --set-interpreter "$(<$NIX_CC/nix-support/dynamic-linker)" {}
      pnpm run build
    '';

    checkPhase = ''
      pnpm run test:unit --run
    '';

    installPhase = ''
      cp -r dist/ $out
    '';
  });

  # Injects a `t.Skip()` into a given test since there's apparently no other way to skip tests here.
  skipTest =
    lineOffset: testCase: file:
    let
      jumpAndAppend = lib.concatStringsSep ";" (lib.replicate (lineOffset - 1) "n" ++ [ "a" ]);
    in
    ''
      sed -i -e '/${testCase}/{
      ${jumpAndAppend} t.Skip();
      }' ${file}
    '';
in
buildGoModule {
  inherit src version;
  pname = "vikunja";

  nativeBuildInputs =
    let
      fakeGit = writeShellScriptBin "git" ''
        if [[ $@ = "describe --tags --always --abbrev=10" ]]; then
            echo "${version}"
        else
            >&2 echo "Unknown command: $@"
            exit 1
        fi
      '';
    in
    [
      fakeGit
      mage
    ];

  vendorHash = "sha256-Fj45v51nXvSOqbxkcWHJE+kgUQ8w7UGm8YeWqTu1HYM=";

  inherit frontend;

  prePatch = ''
    cp -r ${frontend} frontend/dist
  '';

  postConfigure = ''
    # These tests need internet, so we skip them.
    ${skipTest 1 "TestConvertTrelloToVikunja" "pkg/modules/migration/trello/trello_test.go"}
    ${skipTest 1 "TestConvertTodoistToVikunja" "pkg/modules/migration/todoist/todoist_test.go"}
  '';

  buildPhase = ''
    runHook preBuild

    # Fixes "mkdir /homeless-shelter: permission denied" - "Error: error compiling magefiles" during build
    export HOME=$(mktemp -d)
    mage build:build

    runHook postBuild
  '';

  checkPhase = ''
    mage test:unit
    mage test:integration
  '';

  installPhase = ''
    runHook preInstall
    install -Dt $out/bin vikunja
    runHook postInstall
  '';

  passthru.tests.vikunja = nixosTests.vikunja;
}
