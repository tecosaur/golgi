{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  makeWrapper,
  nodejs_22,
  pnpm_10,
  git,
  go,
  ...
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "headplane";
  version = "v0.6.1";

  src = fetchFromGitHub {
    owner = "tale";
    repo = finalAttrs.pname;
    rev = finalAttrs.version;
    hash = "sha256-P92HFuCTIR0Mr86CuAnqT0x+9/136wFIcVTDfJaLGTQ=";
    # Needed for build process
    leaveDotGit = true;
  };

  hp_agent = buildGoModule {
    inherit (finalAttrs) src version;
    pname = "hp_agent";
    vendorHash = "sha256-MvrqKMD+A+qBZmzQv+T9920U5uJop+pjfJpZdm2ZqEA=";
    ldflags = ["-s" "-w"];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "hp_agent";
  };

  hp_wasm = let
    wasmExecJs =
      if builtins.pathExists "${go}/share/go/lib/wasm/wasm_exec.js"
      then "${go}/share/go/lib/wasm/wasm_exec.js"
      else if builtins.pathExists "${go}/lib/wasm/wasm_exec.js"
      then "${go}/lib/wasm/wasm_exec.js"
      else "${go}/share/go/misc/wasm/wasm_exec.js";
  in buildGoModule {
    inherit (finalAttrs) src version;
    pname = "hp_ssh";
    subPackages = ["cmd/hp_ssh"];
    vendorHash = "sha256-MvrqKMD+A+qBZmzQv+T9920U5uJop+pjfJpZdm2ZqEA=";
    env.CGO_ENABLED = 0;

    nativeBuildInputs = [go];

    buildPhase = ''
      export GOOS=js
      export GOARCH=wasm
      go build -o hp_ssh.wasm ./cmd/hp_ssh
    '';

    installPhase = ''
      mkdir -p $out
      cp hp_ssh.wasm $out/
      cp ${wasmExecJs} $out/wasm_exec.js
    '';
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_22
    pnpm_10.configHook
    git
  ];

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 1;
    hash = "sha256-KyUcaR2Lvu5kT8arr4ZO8rCa5HWXTqmk8C7P8WoYK+c=";
  };

  buildPhase = ''
    runHook preBuild
    cp ${finalAttrs.hp_wasm}/hp_ssh.wasm ./app/hp_ssh.wasm
    cp ${finalAttrs.hp_wasm}/wasm_exec.js ./app/wasm_exec.js
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
    cp -r {build,drizzle,node_modules} $out/share/headplane/
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
