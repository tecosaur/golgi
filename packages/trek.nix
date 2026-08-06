{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs_24
, python3
, srcOnly
, removeReferencesTo
, makeWrapper
, kdePackages
, runCommand
, typescript
}:

let
  nodejs = nodejs_24;
  nodeSources = srcOnly nodejs;
in
buildNpmPackage (finalAttrs: {
  pname = "trek";
  version = "3.4.1";

  src = fetchFromGitHub {
    owner = "liketrek";
    repo = "TREK";
    tag = "v${finalAttrs.version}";
    hash = "sha256-r7Y6vxksX+V4bKCz4MF7K8Ar5UgKIzHoJmjukgR+9Cw=";
  };

  inherit nodejs;

  npmDepsHash = "sha256-m+2OFN8EbyCv+sc5T3TcNxjR5tl9qKMzqyLIqrTrews=";

  nativeBuildInputs = [
    python3
    removeReferencesTo
    makeWrapper
  ];

  # Workspace .bin entries are symlinks, which patchShebangs rewrites in place
  # rather than following — without this vite and tsc stay unexecutable.
  preBuild = ''
    patchShebangs --build node_modules */node_modules
  '';

  buildPhase = ''
    runHook preBuild

    pushd node_modules/better-sqlite3
    npm run build-release --offline --nodedir="${nodeSources}"
    find build -type f -exec remove-references-to -t "${nodeSources}" {} \;
    popd

    npm run build --workspace=shared
    npm run build --workspace=server
    npm run build --workspace=client

    runHook postBuild
  '';

  # npmInstallHook packs a single workspace; this tree is three, so `npm prune` is
  # done by hand. Whole workspaces, since the server reads them relative to itself.
  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --no-save $npmFlags "''${npmFlagsArray[@]}"

    mkdir -p $out/lib/trek
    cp -r node_modules package.json package-lock.json shared server wiki $out/lib/trek/
    rm -rf $out/lib/trek/server/{src,test,node_modules} $out/lib/trek/shared/{src,node_modules}
    cp -r client/dist/. $out/lib/trek/server/public/
    cp -r client/public/fonts $out/lib/trek/server/public/fonts

    # No --chdir and no absolute entry: either would pin the server's writable
    # roots into the store (see passthru.stateLinks).
    makeWrapper ${lib.getExe nodejs} $out/bin/trek \
      --add-flags "--require tsconfig-paths/register" \
      --add-flags "dist/index.js" \
      --set-default KITINERARY_EXTRACTOR_PATH "${lib.getExe' kdePackages.kitinerary "kitinerary-extractor"}"

    runHook postInstall
  '';

  # The client is installed as a static bundle, so its @trek link has no target.
  postFixup = ''
    find $out/lib/trek/node_modules -maxdepth 3 -type l ! -exec test -e {} \; -delete
  '';

  # Every writable path the server touches bottoms out in these two, so a consumer
  # must point them at writable state. `dist` itself must be copied, not linked:
  # node resolves __dirname through symlinks, into the store.
  passthru.stateLinks = [ "data" "uploads" ];

  # Expands a plugin's `<!-- trek:ui -->` marker into the design kit and
  # `window.trek` bridge, as the SDK's `pack` does — a step a git checkout never
  # runs, and the server won't do for it. From this TREK, so the two can't diverge.
  passthru.injectUi = runCommand "trek-inject-ui"
    {
      nativeBuildInputs = [ typescript makeWrapper ];
      meta.mainProgram = "trek-inject-ui";
    }
    ''
      tsc ${finalAttrs.src}/plugin-sdk/src/ui/kit.ts \
        --module commonjs --target es2020 --outDir $out/lib
      cat > $out/lib/inject.js <<'EOF'
      const fs = require('node:fs');
      const { injectTrekUi } = require('./kit.js');
      for (const file of process.argv.slice(2)) {
        const before = fs.readFileSync(file, 'utf8');
        const after = injectTrekUi(before);
        if (after !== before) fs.writeFileSync(file, after);
      }
      EOF
      makeWrapper ${lib.getExe nodejs} $out/bin/trek-inject-ui \
        --add-flags $out/lib/inject.js
    '';

  meta = {
    description = "Self-hosted collaborative travel planner with maps, budgets and journals";
    homepage = "https://github.com/liketrek/TREK";
    changelog = "https://github.com/liketrek/TREK/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "trek";
    platforms = lib.platforms.linux;
  };
})
