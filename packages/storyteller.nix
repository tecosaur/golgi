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
  jre_headless,
  buildGoModule,
  whisper-cpp,
  whisper ? whisper-cpp,
}:

let
  nodeSources = srcOnly nodejs_24;
  yarn-berry = yarn-berry_4;

  readium-cli = buildGoModule rec {
    pname = "readium-cli";
    version = "0.7.1";

    src = fetchFromGitHub {
      owner = "readium";
      repo = "cli";
      rev = "v${version}";
      hash = "sha256-HQd8yw2bA7ILP7rQOwKcFeaGQLx1bsnu67lM1BNkreI=";
    };

    vendorHash = "sha256-OxK8D9s2Q80M4ypQ5z+vrIFQZLQujk/QRuDsir95jJM=";

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

  epubcheckVersion = "5.3.0";

  epubcheckZip = fetchurl {
    url = "https://github.com/w3c/epubcheck/releases/download/v${epubcheckVersion}/epubcheck-${epubcheckVersion}.zip";
    hash = "sha256-bAfmhYSy4s4vif4G4SRt/q0+s2tGs0Dn2TUk8p3P9sU=";
  };

  yarnPatch = ''
    # Add dependenciesMeta to package.json and mirror it into yarn.lock.
    ${nodejs_24}/bin/node <<'JS'
    const fs = require("fs");

    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
    pkg.dependenciesMeta = {
      ...pkg.dependenciesMeta,
      electron: { built: false },
      sqlite3: { built: false },
      "better-sqlite3": { built: false },
      "onnxruntime-node": { built: false },
    };
    fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");

    const lockPath = "yarn.lock";
    let lock = fs.readFileSync(lockPath, "utf8");

    const resolution = '  resolution: "' + pkg.name + '@workspace:."';
    const rootEntry = lock.indexOf(resolution);

    if (rootEntry === -1) {
      throw new Error("Could not find root workspace entry: " + resolution);
    }

    const nextEntry = lock.indexOf('\n"', rootEntry + resolution.length);
    const blockEnd = nextEntry === -1 ? lock.length : nextEntry + 1;
    const rootBlock = lock.slice(rootEntry, blockEnd);

    const languageName = lock.indexOf("  languageName:", rootEntry);

    if (languageName === -1 || languageName >= blockEnd) {
      throw new Error("Could not find insertion point in root workspace entry");
    }

    if (!rootBlock.includes("  dependenciesMeta:\n")) {
      const metaText =
        "  dependenciesMeta:\n" +
        "    electron:\n" +
        "      built: false\n" +
        "    onnxruntime-node:\n" +
        "      built: false\n" +
        "    better-sqlite3:\n" +
        "      built: false\n" +
        "    sqlite3:\n" +
        "      built: false\n";

      lock = lock.slice(0, languageName) + metaText + lock.slice(languageName);
      fs.writeFileSync(lockPath, lock);
    }
    JS
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "storyteller";
  version = "2.14.10";

  src = fetchFromGitLab {
    owner = "storyteller-platform";
    repo = "storyteller";
    # rev = "web-v${finalAttrs.version}";
    rev = "8e14b0c5e95e04288c9f5fec4d0d5dd017353a3b";
    hash = "sha256-V1ppXL3Y+4XUvZBenoryCZAy9vUAWkXg0QoHZJ5ODnw=";
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
    postPatch = yarnPatch;
    hash = "sha256-9Qp218XCKWOlzpyEXtIGkqq2C+KYPovKkG3S7sCFh88=";
  };

  passthru = {
    inherit (finalAttrs) offlineCache;
  };

  buildInputs = [
    sqlite.dev
  ];

  postPatch = yarnPatch;

  # After the yarn configure, build native modules that need special handling.
  preBuild = ''
    # EPUBCheck is stored upstream through Git LFS. Fetch and extract it
    # explicitly for the Nix build.
    mkdir -p libraries/epub/vendors
    unzip -q ${epubcheckZip} -d libraries/epub/vendors

    if [[ ! -f libraries/epub/vendors/epubcheck-${epubcheckVersion}/epubcheck.jar ]]; then
      echo "ERROR: epubcheck-${epubcheckVersion}/epubcheck.jar missing"
      find libraries/epub/vendors -maxdepth 3 -print
      exit 1
    fi

    # Build the native part of all instances of better-sqlite3.
    # Adapted from mkYarnModules.
    for f in $(find -path '*/node_modules/better-sqlite3' -type d); do
      (cd "$f" && (
      npm run build-release --offline --nodedir="${nodeSources}"
      find build -type f -exec \
        ${lib.getExe removeReferencesTo} \
        -t "${nodeSources}" {} \;
      ))
    done

    # The checked-out Align prebuilds may be Git LFS pointer files. Rebuild
    # the native addon against the Nix toolchain and replace the x86-64
    # prebuild with the resulting binary.
    (
      cd libraries/align
      npm_config_nodedir="${nodeSources}" yarn node-gyp rebuild

      ${lib.getExe removeReferencesTo} \
        -t "${nodeSources}" \
        build/Release/error_align_native.node

      mkdir -p prebuilds/linux-x64
      cp -f \
        build/Release/error_align_native.node \
        prebuilds/linux-x64/@storyteller-platform+align.node
    )
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
    gcc -O2 -g -fPIC -rdynamic -shared applications/web/sqlite/uuid.c -o applications/web/sqlite/uuid.c.so
    # Native bindings used while building the worker and Next.js application
    export SQLITE_NATIVE_BINDING="$PWD/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
    export ERROR_ALIGN_NATIVE_BINDING="$PWD/libraries/align"
    # Do the build!
    yarn workspaces foreach -Rpt --from @storyteller-platform/web --exclude @storyteller-platform/eslint run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,lib/storyteller}
    # Standalone Next.js output
    if [[ ! -d applications/web/.next/standalone ]]; then
      echo "ERROR: Next.js standalone output not found"
      exit 1
    fi
    cp -r applications/web/.next/standalone/. $out/lib/storyteller/
    mkdir -p $out/lib/storyteller/applications/web/public
    cp -r applications/web/public/. $out/lib/storyteller/applications/web/public/
    mkdir -p $out/lib/storyteller/applications/web/.next/static
    cp -r applications/web/.next/static/. $out/lib/storyteller/applications/web/.next/static/
    # SQLite extension
    mkdir -p $out/lib/storyteller/applications/web/sqlite
    cp applications/web/sqlite/uuid.c.so $out/lib/storyteller/applications/web/sqlite/
    # Migrations
    cp -r applications/web/migrations $out/lib/storyteller/applications/web/migrations
    # Scripts
    mkdir -p $out/lib/storyteller/applications/web/scripts
    cp -r scripts/. $out/lib/storyteller/applications/web/scripts/
    cp -r docker-scripts/. $out/lib/storyteller/applications/web/scripts/
    # Workers
    cp -r applications/web/work-dist $out/lib/storyteller/applications/web/work-dist
    cp -r applications/web/file-write-dist $out/lib/storyteller/applications/web/file-write-dist
    # Align
    mkdir -p $out/lib/storyteller/applications/web/work-dist/@storyteller-platform/align/prebuilds/linux-x64
    cp -r libraries/align/prebuilds/linux-x64/. \
      $out/lib/storyteller/applications/web/work-dist/@storyteller-platform/align/prebuilds/linux-x64/
    # Echogarden wasm
    cp node_modules/@echogarden/icu-segmentation-wasm/wasm/*.wasm \
      $out/lib/storyteller/applications/web/work-dist/
    # EPUBCheck
    mkdir -p $out/lib/storyteller/applications/web/work-dist/vendors
    cp -r libraries/epub/vendors/epubcheck-${epubcheckVersion} \
      $out/lib/storyteller/applications/web/work-dist/vendors/
    # Runtime packages loaded dynamically and not fully traced by Next.js
    mkdir -p $out/lib/storyteller/node_modules/@parcel
    cp -r node_modules/@parcel/. \
      $out/lib/storyteller/node_modules/@parcel/
    mkdir -p $out/lib/storyteller/node_modules/kuromoji
    cp -r node_modules/kuromoji/. \
      $out/lib/storyteller/node_modules/kuromoji/
    # Extract whisper.cpp version from ghost-story source
    whisperCppUpstreamVersion=$(grep -oP 'WHISPER_CPP_UPSTREAM_VERSION\s*=\s*"\K[^"]+' libraries/ghost-story/src/constants.ts)
    whisperCppPatchLevel=$(grep -oP 'WHISPER_CPP_PATCH_LEVEL\s*=\s*\K[0-9]+' libraries/ghost-story/src/constants.ts)
    whisperCppVersion="''${whisperCppUpstreamVersion}-st.''${whisperCppPatchLevel}"
    # Native binding
    mkdir -p $out/lib/storyteller/node_modules/better-sqlite3/build/Release
    cp node_modules/better-sqlite3/build/Release/better_sqlite3.node \
       $out/lib/storyteller/node_modules/better-sqlite3/build/Release/
    # Wrapper
    makeWrapper ${nodejs_24}/bin/node $out/bin/storyteller \
      --add-flags "--enable-source-maps $out/lib/storyteller/applications/web/server.js" \
      --chdir "$out/lib/storyteller/applications/web" \
      --run "WHISPER_DIR=\"\$HOME/.local/share/ghost-story/whisper-cpp/$whisperCppVersion/linux-x64-cpu/bin\"; mkdir -p \"\$WHISPER_DIR\"; ln -sfn ${whisper}/bin/whisper-cli \"\$WHISPER_DIR/whisper-cli\"" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg readium-cli jre_headless ]} \
      --set NODE_ENV "production" \
      --set NEXT_TELEMETRY_DISABLED "1" \
      --set CI_COMMIT_TAG "web-v${finalAttrs.version}" \
      --set STORYTELLER_LOG_LEVEL "debug" \
      --set STORYTELLER_WHISPER_VARIANT "linux-x64-cpu" \
      --set STORYTELLER_WORKER "worker.mjs" \
      --set STORYTELLER_FILE_WRITE_WORKER "fileWriteWorker.mjs" \
      --set SQLITE_NATIVE_BINDING "$out/lib/storyteller/node_modules/better-sqlite3/build/Release/better_sqlite3.node" \
      --set ERROR_ALIGN_NATIVE_BINDING "$out/lib/storyteller/applications/web/work-dist/@storyteller-platform/align"
    runHook postInstall
  '';

  meta = {
    description = "Self-hosted platform for synced audiobook/ebook reading";
    homepage = "https://storyteller-platform.gitlab.io/storyteller/";
    changelog = "https://gitlab.com/storyteller-platform/storyteller/-/releases/web-v${finalAttrs.version}";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "storyteller";
  };
})
