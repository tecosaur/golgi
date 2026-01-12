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
  # Fonts for offline build (next/font/google requires network at build time)
  inter-font = fetchurl {
    url = "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip";
    hash = "sha256-mIP91KSdT7Zr2Bd7pmJe+aZKpFiZdn3ePTaqQldWsR4=";
  };
  young-serif-font = fetchurl {
    url = "https://github.com/noirblancrouge/YoungSerif/raw/master/fonts/otf/YoungSerif-Regular.otf";
    hash = "sha256-UGEll/kYrBjphcD/T2VkpUv3J0fyBXBVCgYGWf8uyz8=";
  };
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
  version = "2.6.1";

  src = fetchFromGitLab {
    owner = "tecosaur";
    repo = "storyteller";
    # rev = "web-v${finalAttrs.version}";
    rev = "ed212f5ced9f706a0eee6d8191f9495cae2b3d70";
    hash = "sha256-XZUUyWMgMbVm8WSLg3hemYtl4tkX6ylXZSDQ1g/k8fw=";
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
    hash = "sha256-b2rdeNVoiNGhaX57ZnGOjRweOFh54VRFWCtn6QAAzHE=";
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
    # Set up local fonts for offline build (next/font/google requires network)
    mkdir -p web/src/app/fonts
    unzip -j ${inter-font} "InterVariable.ttf" -d web/src/app/fonts
    cp ${young-serif-font} web/src/app/fonts/YoungSerif-Regular.otf
    # Patch layout.tsx to use local fonts instead of Google Fonts
    substituteInPlace web/src/app/layout.tsx \
          --replace-warn 'import { Inter, Young_Serif } from "next/font/google"' 'import localFont from "next/font/local"' \
          --replace-warn 'const inter = Inter({
      subsets: ["latin"],
      display: "swap",
      variable: "--font-inter",
    })' 'const inter = localFont({
      src: "./fonts/InterVariable.ttf",
      display: "swap",
      variable: "--font-inter",
    })' \
          --replace-warn 'const youngSerif = Young_Serif({
      subsets: ["latin"],
      display: "swap",
      weight: "400",
      variable: "--font-young-serif",
    })' 'const youngSerif = localFont({
      src: "./fonts/YoungSerif-Regular.otf",
      display: "swap",
      variable: "--font-young-serif",
    })'
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
    # Workers
    yarn workspace @storyteller-platform/web run build:worker
    yarn workspace @storyteller-platform/web run build:file-write-worker
    # Next.js
    yarn workspace @storyteller-platform/web run build
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
    # WASM files for echogarden speech processing
    cp node_modules/@echogarden/speex-resampler-wasm/wasm/*.wasm $out/lib/storyteller/web/work-dist/
    cp node_modules/@echogarden/pffft-wasm/dist/simd/pffft.wasm $out/lib/storyteller/web/work-dist/
    cp node_modules/tiktoken/lite/tiktoken_bg.wasm $out/lib/storyteller/web/work-dist/
    cp node_modules/@echogarden/espeak-ng-emscripten/espeak-ng.data $out/lib/storyteller/web/work-dist/
    # Echogarden data and dist (manually resolved by echogarden at runtime)
    mkdir -p $out/lib/storyteller/{data,dist}
    cp -r node_modules/echogarden/data/* $out/lib/storyteller/data/
    cp -r node_modules/echogarden/dist/* $out/lib/storyteller/dist/
    # Pre-built whisper.cpp (Storyteller expects whisper-builds/cpu/build/bin/whisper-cli relative to cwd)
    mkdir -p $out/lib/storyteller/web/whisper-builds/cpu/build/bin
    ln -s ${whisper}/bin/whisper-cli $out/lib/storyteller/web/whisper-builds/cpu/build/bin/whisper-cli
    # Native binding
    mkdir -p $out/lib/storyteller/node_modules/better-sqlite3/build/Release
    cp node_modules/better-sqlite3/build/Release/better_sqlite3.node \
       $out/lib/storyteller/node_modules/better-sqlite3/build/Release/
    # Wrapper
    makeWrapper ${nodejs_24}/bin/node $out/bin/storyteller \
      --add-flags "--enable-source-maps $out/lib/storyteller/web/server.js" \
      --chdir "$out/lib/storyteller/web" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg readium-cli ]} \
      --set CI_COMMIT_TAG "web-v${finalAttrs.version}" \
      --set STORYTELLER_WORKER "worker.cjs" \
      --set STORYTELLER_FILE_WRITE_WORKER "fileWriteWorker.cjs" \
      --set SQLITE_NATIVE_BINDING "$out/lib/storyteller/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
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
