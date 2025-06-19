{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  makeWrapper,
  nodejs_22,
  pnpm_10,
  git,
  ...
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "headplane";
  version = "v0.6.0";

  src = fetchFromGitHub {
    owner = "tale";
    repo = finalAttrs.pname;
    tag = finalAttrs.version;
    hash = "sha256-IRQw59eefznj0jVrn/3aGX3VAof2MsRIn5Iyoh42RDI=";
    # Needed for build process
    leaveDotGit = true;
  };

  hp_agent = buildGoModule {
    inherit (finalAttrs) src version;
    pname = "hp_agent";
    vendorHash = "sha256-5TmX9ZUotNC3ZnNWRlyugAmzQG/WSZ66jFfGljql/ww=";
    ldflags = ["-s" "-w"];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "hp_agent";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_22
    pnpm_10.configHook
    git
  ];

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-OOWgYaGwa5PtWhFEEkRCojCDmkPIR6tJ5cfFMOLND3I=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    pnpm prune --prod
    # Clean up broken symlinks left behind by `pnpm prune`
    # https://github.com/pnpm/pnpm/issues/3645
    find node_modules -xtype l -delete
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,share/headplane}
    # build directory needs to be present at runtime:
    # https://github.com/tale/headplane/blob/0.4.1/docs/integration/Native.md
    # node_modules seems to be required as well
    cp -r {build,node_modules} $out/share/headplane/
    # Ugly hacks (why!?!)
    sed -i "s;$PWD;../..;" $out/share/headplane/build/server/index.js
    makeWrapper ${lib.getExe nodejs_22} $out/bin/headplane \
        --chdir $out/share/headplane \
        --set BUILD_PATH $out/share/headplane/build \
        --set NODE_ENV production \
        --add-flags $out/share/headplane/build/server/index.js
    # Copy the agent over
    cp ${lib.getExe finalAttrs.hp_agent} $out/bin/hp_agent
    runHook postInstall
  '';
})
