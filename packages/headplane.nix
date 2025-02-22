{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
  pnpm_9,
  git,
  ...
}:

# Source: <https://gist.github.com/feathecutie/8ebc00237bcdefd517e6b65f5ea5e0dc>.

stdenv.mkDerivation (finalAttrs: {
  pname = "headplane";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "tale";
    repo = finalAttrs.pname;
    tag = finalAttrs.version;
    hash = "sha256-2M0OpTIFfsF7khZviaAGIhKV7zEtX2ks6D6xfujmFMk=";
    # Needed for build process
    leaveDotGit = true;
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm_9.configHook
    git
  ];

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-W0ba9xvs1LRKYLjO7Ldmus4RrJiEbiJ7+Zo92/ZOoMQ=";
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
    sed -i 's;/build/source/node_modules/react-router/dist/development/index.mjs;react-router;' $out/share/headplane/build/headplane/server.js
    sed -i 's;define_process_env_default.PORT;process.env.PORT;' $out/share/headplane/build/headplane/server.js
    makeWrapper ${lib.getExe nodejs} $out/bin/headplane \
        --chdir $out/share/headplane \
        --set BUILD_PATH $out/share/headplane/build \
        --set NODE_ENV production \
        --add-flags $out/share/headplane/build/headplane/server.js
    runHook postInstall
  '';
})
