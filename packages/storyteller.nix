{
  lib,
  stdenv,
  fetchFromGitLab,
  fetchFromGitHub,
  fetchurl,
  yarn-berry_4,
  nodejs_24,
  srcOnly,
  removeReferencesTo,
  makeWrapper,
  ffmpeg,
  sqlite,
  gcc,
  python3,
  git,
  unzip,
  buildGoModule,
  whisper-cpp,
  whisper ? whisper-cpp,
}:

let
  nodeSources = srcOnly nodejs_24;
  yarn-berry = yarn-berry_4;
  readium-cli = buildGoModule rec {
    pname = "readium-cli";
    version = "0.6.3";

    src = fetchFromGitHub {
      owner = "readium";
      repo = "cli";
      rev = "v${version}";
      hash = "sha256-8SvzmjmzF2FbU4A7As7LT8xNcY1EY55AX2tsHM3whV0=";
    };

    vendorHash = "sha256-go0SFoijiYk8Eg7ahssKypR+jOw4NYVfJsBJIyNLYz0=";

    subPackages = [ "cmd" ];

    postInstall = ''
      mv $out/bin/cmd $out/bin/readium
    '';

    meta = {
      description = "Readium CLI for EPUB processing and streaming";
      homepage = "https://github.com/readium/cli";
      license = lib.licenses.bsd3;
      mainProgram = "readium";
    };
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "storyteller";
  version = "2.11.9";

  src = fetchFromGitLab {
    owner = "tecosaur";
    repo = "storyteller";
    # rev = "web-v${finalAttrs.version}";
    rev = "c25a7d1e04d3460f3ad5721d22e7801c78154fbf";
    hash = "sha256-ENoCWFx9gJ72H/WrlPLHGqgyXbbnzfZ9PiyOomWDBx8=";
  };

  nativeBuildInputs = [
    nodejs_24
    yarn-berry
    yarn-berry.yarnBerryConfigHook
    makeWrapper
    gcc
    python3
    git
    unzip
  ];

  missingHashes = ./storyteller-missing-yarn-hashes.json; # From `nix run 'nixpkgs#yarn-berry_4.yarn-berry-fetcher' missing-hashes yarn.lock`
  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src missingHashes;
    hash = "sha256-dbGlcHL7cNk1eMYUXzAQ9kkkvERUhXyqTx7QgJjIo6g=";
  };

  buildInputs = [
    sqlite.dev
  ];

  postPatch = ''
    # Add dependenciesMeta to package.json to skip building problematic packages
    ${nodejs_24}/bin/node -e "
      const fs = require('fs');
      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
      pkg.dependenciesMeta = {
        ...pkg.dependenciesMeta,
        'electron': { built: false },
        'sqlite3': { built: false },
        'onnxruntime-node': { built: false },
      };
      fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
    "
  '';

  # After the pnpm configure, we need to build the binaries of all instances
  # of better-sqlite3. It has a native part that it wants to build using a
  # script which is disallowed.
  # Adapted from mkYarnModules.
  preBuild = ''
    for f in $(find -path '*/node_modules/better-sqlite3' -type d); do
      (cd "$f" && (
      npm run build-release --offline --nodedir="${nodeSources}"
      find build -type f -exec \
        ${lib.getExe removeReferencesTo} \
        -t "${nodeSources}" {} \;
      ))
    done
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export NODE_ENV=production
    export NEXT_TELEMETRY_DISABLED=1
    export CI_COMMIT_TAG=web-v${finalAttrs.version}
    export npm_config_cache="$TMPDIR/.npm-cache"
    mkdir -p "$npm_config_cache"
    # SQLite UUID extension
    gcc -O2 -g -fPIC -rdynamic -shared web/sqlite/uuid.c -o web/sqlite/uuid.c.so
    # Do the build!
    export ERROR_ALIGN_NATIVE_BINDING="$PWD/align"
    yarn workspaces foreach -Rpt --from @storyteller-platform/web --exclude @storyteller-platform/eslint run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,lib/storyteller}
    # Standalone Next.js output
    if [[ ! -d web/.next/standalone ]]; then
      echo "ERROR: Next.js standalone output not found"
      exit 1
    fi
    cp -r web/.next/standalone/* $out/lib/storyteller/
    mkdir -p $out/lib/storyteller/web/public
    cp -r web/public/* $out/lib/storyteller/web/public/
    mkdir -p $out/lib/storyteller/web/.next/static
    cp -r web/.next/static/* $out/lib/storyteller/web/.next/static/
    # Align
    mkdir -p $out/lib/storyteller/web/work-dist/@storyteller-platform/align/prebuilds
    cp -r align/prebuilds/linux-x64 $out/lib/storyteller/web/work-dist/@storyteller-platform/align/prebuilds/
    cp -r align/prebuilds/linux-arm64 $out/lib/storyteller/web/work-dist/@storyteller-platform/align/prebuilds/
    # SQLite extension
    mkdir -p $out/lib/storyteller/web/sqlite
    cp web/sqlite/uuid.c.so $out/lib/storyteller/web/sqlite/
    # Migrations
    cp -r web/migrations $out/lib/storyteller/web/migrations
    # Workers
    mkdir -p $out/lib/storyteller/web/work-dist
    cp web/work-dist/*.cjs $out/lib/storyteller/web/work-dist/
    mkdir -p $out/lib/storyteller/web/file-write-dist
    cp web/file-write-dist/*.cjs $out/lib/storyteller/web/file-write-dist/
    # Echogarden wasm
    cp node_modules/@echogarden/icu-segmentation-wasm/wasm/*.wasm $out/lib/storyteller/web/work-dist/
    # Pre-built whisper.cpp (Storyteller expects whisper-builds/cpu/build/bin/whisper-cli relative to cwd)
    mkdir -p $out/lib/storyteller/web/whisper-builds/cpu/build/bin
    ln -s ${whisper}/bin/whisper-cli $out/lib/storyteller/web/whisper-builds/cpu/build/bin/whisper-cli
    # Native binding
    mkdir -p $out/lib/storyteller/node_modules/better-sqlite3/build/Release
    cp node_modules/better-sqlite3/build/Release/better_sqlite3.node \
       $out/lib/storyteller/node_modules/better-sqlite3/build/Release/
    # Extract whisper.cpp version from ghost-story source
    whisperCppUpstreamVersion=$(grep -oP 'WHISPER_CPP_UPSTREAM_VERSION\s*=\s*"\K[^"]+' ghost-story/src/constants.ts)
    whisperCppPatchLevel=$(grep -oP 'WHISPER_CPP_PATCH_LEVEL\s*=\s*\K[0-9]+' ghost-story/src/constants.ts)
    whisperCppVersion="''${whisperCppUpstreamVersion}-st.''${whisperCppPatchLevel}"
    # Wrapper
    makeWrapper ${nodejs_24}/bin/node $out/bin/storyteller \
      --add-flags "--enable-source-maps $out/lib/storyteller/web/server.js" \
      --chdir "$out/lib/storyteller/web" \
      --run "WHISPER_DIR=\"\$HOME/.local/share/ghost-story/whisper-cpp/$whisperCppVersion/linux-x64-cpu/bin\"; mkdir -p \"\$WHISPER_DIR\"; ln -sfn ${whisper}/bin/whisper-cli \"\$WHISPER_DIR/whisper-cli\"" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg readium-cli ]} \
      --set CI_COMMIT_TAG "web-v${finalAttrs.version}" \
      --set STORYTELLER_WORKER "worker.cjs" \
      --set STORYTELLER_FILE_WRITE_WORKER "fileWriteWorker.cjs" \
      --set SQLITE_NATIVE_BINDING "$out/lib/storyteller/node_modules/better-sqlite3/build/Release/better_sqlite3.node" \
      --set ERROR_ALIGN_NATIVE_BINDING "$out/lib/storyteller/web/work-dist/@storyteller-platform/align"
    runHook postInstall
  '';

  meta = {
    description = "Self-hosted platform for synced audiobook/ebook reading";
    homepage = "https://storyteller-platform.gitlab.io/storyteller/";
    changelog = "https://gitlab.com/storyteller-platform/storyteller/-/releases/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "storyteller";
  };
})
