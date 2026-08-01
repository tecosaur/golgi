# Largely copied from <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/vi/vikunja/package.nix>

{
  lib,
  fetchFromGitHub,
  stdenv,
  nodejs_24,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  buildGoModule,
  mage,
  dart-sass,
  writeShellScriptBin,
  nixosTests,
  vikunja-assets
}:

let
  version = "2.4.0";
  src = fetchFromGitHub {
    owner = "go-vikunja";
    repo = "vikunja";
    rev = "v${version}";
    hash = "sha256-0yAFrq+qzLZLXPblWY2lkoJ2idzENR3YqdFNiDqep6U=";
  };

  frontend = stdenv.mkDerivation (finalAttrs: {
    pname = "vikunja-frontend";
    inherit version src;

    sourceRoot = "${finalAttrs.src.name}/frontend";

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        sourceRoot
        ;
      pnpm = pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-MnkwuEaBEY81LXInDao2Fi+FvKFyvsVS/QeXdS4FhPQ=";
    };

    nativeBuildInputs = [
      nodejs_24
      dart-sass
      pnpmConfigHook
      pnpm_10
    ];

    postPatch = ''
      substituteInPlace src/version.json \
        --replace-fail '"dev"' '"${finalAttrs.version}"'
      # Webpage theming
      cp -f ${vikunja-assets}/frontend/* frontend/src/assets
      substituteInPlace frontend/src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-h: 217deg" "--primary-h: 146deg"
      substituteInPlace frontend/src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-s: 98%" "--primary-s: 56%"
      substituteInPlace frontend/src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-l: 53%" "--primary-l: 37%"
      substituteInPlace frontend/src/styles/custom-properties/colors.scss --replace-warn \
        "--primary-l: 58%" "--primary-l: 42%"
      # PWA theming
      substituteInPlace frontend/vite.config.ts --replace-warn \
        "1973ff" "239a58"
    '';

    doCheck = true;

    postBuild = ''
      # Force sass-embedded to use our dart-sass instead of bundled binaries.
      substituteInPlace node_modules/sass-embedded/dist/lib/src/compiler-path.js \
        --replace-fail 'compilerCommand = (() => {' 'compilerCommand = (() => { return ["${lib.getExe dart-sass}"];'
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

  vendorHash = "sha256-4JOwr6QCWglxXbRkcko2nsAxEhVbHDO1S2vI91NFM/8=";

  inherit frontend;

  prePatch = ''
    cp -r ${frontend} frontend/dist
  '';

  postConfigure = ''
    # These tests need internet, so we skip them.
    ${skipTest 1 "TestConvertTrelloToVikunja" "pkg/modules/migration/trello/trello_test.go"}
    ${skipTest 1 "TestConvertTodoistToVikunja" "pkg/modules/migration/todoist/todoist_test.go"}
    # These tests require a full config with public URL and CORS enabled.
    ${skipTest 1 "TestCreateOrganizationMap" "pkg/modules/migration/trello/trello_test.go"}
    ${skipTest 1 "TestTaskAttachmentUploadSize" "pkg/webtests/task_attachment_upload_test.go"}
  '';

  buildPhase = ''
    runHook preBuild

    # Fixes "mkdir /homeless-shelter: permission denied" - "Error: error compiling magefiles" during build
    export HOME=$(mktemp -d)
    mage build:build

    runHook postBuild
  '';

  checkPhase = ''
    mage test:feature
    mage test:web
  '';

  installPhase = ''
    runHook preInstall
    install -Dt $out/bin vikunja
    runHook postInstall
  '';

  passthru = {
    tests.vikunja = nixosTests.vikunja;
    frontend = frontend;
    updateScript = ./update.sh;
  };

  meta = {
    changelog = "https://github.com/go-vikunja/vikunja/blob/v${version}/CHANGELOG.md";
    description = "Todo-app to organize your life";
    homepage = "https://vikunja.io/";
    license = lib.licenses.agpl3Plus;
    maintainers = with lib.maintainers; [
      leona
      adamcstephens
    ];
    mainProgram = "vikunja";
    platforms = lib.platforms.linux;
  };
}
