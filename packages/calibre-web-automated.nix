{ lib
, stdenv
, fetchFromGitHub
, python3Packages
}:

python3Packages.buildPythonApplication rec {
  pname = "calibre-web-automated";
  version = "3.1.5-pre1";
  pyproject = true;

  srcs = [
    (fetchFromGitHub {
      name = "cw-automated";
      owner = "crocodilestick";
      repo  = "Calibre-Web-Automated";
      rev   = "0d2ce74fa32b4f3d632baaa4411dc3e5af1a230c"; # "V${version}";
      hash  = "sha256-Fm7IpnYOhieKNFzDjYn3B3awCtLZzFJaOYiSPbENiHI=";
    })
    (fetchFromGitHub {
      name = "calibre-web";
      owner = "janeczku";
      repo  = "calibre-web";
      rev   = "0.6.24"; # `CALIBREWEB_RELEASE` from <https://github.com/crocodilestick/Calibre-Web-Automated/blob/main/Dockerfile#L28>
      hash  = "sha256-DYhlD3ly6U/e5cDlsubDyW1uKeCtB+HrpagJlNDJhyI=";
    })
  ];

  sourceRoot = ".";

  build-system = with python3Packages; [ setuptools ];

  dependencies = with python3Packages; [
    apscheduler
    babel
    bleach
    certifi
    chardet
    charset-normalizer
    cryptography
    flask
    flask-babel
    flask-httpauth
    flask-limiter
    flask-principal
    flask-wtf
    idna
    iso-639
    lxml
    pycountry
    pypdf
    python-magic
    pytz
    polib
    qrcode
    regex
    requests
    sqlalchemy
    tabulate
    tornado
    unidecode
    netifaces-plus
    urllib3
    wand
  ];

  optional-dependencies = {
    comics = with python3Packages; [
      comicapi
      natsort
    ];

    gdrive = with python3Packages; [
      gevent
      google-api-python-client
      greenlet
      httplib2
      oauth2client
      pyasn1-modules
      # https://github.com/NixOS/nixpkgs/commit/bf28e24140352e2e8cb952097febff0e94ea6a1e
      # pydrive2
      pyyaml
      rsa
      uritemplate
    ];

    gmail = with python3Packages; [
      google-api-python-client
      google-auth-oauthlib
    ];

    # We don't support the goodreads feature, as the `goodreads` package is
    # archived and depends on other long unmaintained packages (rauth & nose)
    # goodreads = [ ];

    kobo = with python3Packages; [ jsonschema ];

    ldap = with python3Packages; [
      flask-simpleldap
      python-ldap
    ];

    metadata = with python3Packages; [
      beautifulsoup4
      faust-cchardet
      html2text
      markdown2
      mutagen
      py7zr
      pycountry
      python-dateutil
      rarfile
      scholarly
    ];

    oauth = with python3Packages; [
      flask-dance
      sqlalchemy-utils
    ];
  };

  pythonRelaxDeps = [
    "flask-babel"
    "pypdf"
    "unidecode"
    "lxml"
    "regex"
    "cryptography"
  ];

  nativeBuildInputs = [ python3Packages.wrapPython ];

  nativeCheckInputs = lib.flatten (lib.attrValues optional-dependencies);

  # calibre-web doesn't follow setuptools directory structure.
  postPatch = ''
    cp -r cw-automated/* .

    substituteInPlace cps/logger.py \
      --replace-fail 'os.path.join(_CONFIG_DIR, "calibre-web.log")' '"/dev/stdout"'
    substituteInPlace cps/logger.py \
      --replace-fail 'os.path.join(_CONFIG_DIR, "access.log")' '"/dev/stdout"'

    # Fix the hardcoded sys.path to be relative to the current file
    substituteInPlace cps/render_template.py \
    --replace-fail 'import sys' 'import sys, os' \
    --replace-fail "sys.path.insert(1, '/app/calibre-web-automated/scripts/')" \
    'sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(__file__)), "scripts"))'

    find . -name '*.py' -exec sed -i "s;/app/calibre-web-automated/metadata_temp;config/metadata_temp;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/calibre-web-automated/metadata_change_logs;config/metadata_change_logs;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/calibre-web-automated/scripts/\(.*\)\.py;$out/bin/\1;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/calibre-web-automated/scripts;$out/${python3Packages.python.sitePackages}/calibreweb/scripts;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/calibre-web-automated;$out/share/calibre-web-automated;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/cwa_update_notice;config/cwa_update_notice;g" {} \;
    find . -name '*.py' -exec sed -i "s;/app/;$out/share/calibre-web-automated/;g" {} \;

    find . -name '*.py' -exec sed -i -e 's;/config/;config/;g' -e "s;\([\"']\)/config;\1config;g" {} \;
    find . -name '*.py' -exec sed -i "s;/calibre-library;calibre-library;g" {} \;

    find . -name '*.py' -exec sed -i 's;^\([ 	]*\).*chown[("].*$;\1pass;g' {} \;
    sed -i -e "/nbp.set_l\|self.set_l/d" -e "/def set_libr/,/^$/d" \
      scripts/{convert_library.py,kindle_epub_fixer.py,ingest_processor.py}
    sed -i '/def update_dirs_json(self):/a\        return print("[cwa-auto-library]: Skipping updating dirs.json")' scripts/auto_library.py
    sed -i -e '/uid =/d' -e '/gid =/d' scripts/kindle_epub_fixer.py
    sed -i "s;'python3', '\($out/bin/.*\)';'\1';" cps/cwa_functions.py

    bash scripts/compile_translations.sh # Needs to be done before we move the `cps` folder

    mkdir -p src/calibreweb
    mv cps.py src/calibreweb/__init__.py
    mv cps src/calibreweb
    cp -r scripts src/calibreweb

    substituteInPlace pyproject.toml \
      --replace-fail 'cps = "calibreweb:main"' 'calibre-web = "calibreweb:main"'
  '';

  preBuild = ''
  mkdir -p $out
  mv src/calibreweb/cps/translations $out/translations
  '';

  postInstall = ''
  cat $out/bin/calibre-web | sed '/exec/d' > $out/bin/cwa-python-path-setup

  mkdir -p $out/share/calibre-web-automated

  for f in $out/${python3Packages.python.sitePackages}/calibreweb/scripts/*.py; do
      fplain="''${f%.py}"
      makeWrapper \
        ${python3Packages.python.interpreter} \
        "$out/bin/$(basename "$fplain")" \
        --add-flags "$f" \
        --prefix PYTHONPATH : "$PYTHONPATH"
  done

  for f in scripts/*; do
      if [[ "$f" != *.py ]]; then
          cp "$f"  $out/${python3Packages.python.sitePackages}/calibreweb/scripts/
      fi
  done

  srcs_arr=($srcs)
  cwa_src=''${srcs_arr[0]}
  calibre_web_src=''${srcs_arr[1]}

  cp -r $cwa_src/empty_library $out/share/calibre-web-automated
  cp -r $cwa_src/koreader $out/share/calibre-web-automated
  mkdir -p $out/share/calibre-web
  cp -r $calibre_web_src/* $out/share/calibre-web

  echo "${version}" > $out/share/calibre-web-automated/CWA_RELEASE
  cp $out/share/calibre-web-automated/CWA_RELEASE $out/share/calibre-web-automated/CWA_STABLE_RELEASE
  cp $cwa_src/dirs.json $out/share/calibre-web-automated/dirs.json
  sed -i 's;"/;";g' $out/share/calibre-web-automated/dirs.json

  cp -r $cwa_src/cps/templates $out/${python3Packages.python.sitePackages}/calibreweb/cps/templates
  mv $out/translations $out/${python3Packages.python.sitePackages}/calibreweb/cps

  sed -i -n '/Linuxserver.io/{x;d;};1h;1!{x;p;};''${x;p;}' $out/${python3Packages.python.sitePackages}/calibreweb/cps/templates/admin.html &&
    sed -i -e "/Linuxserver.io/,+3d" -e "s/commit/calibreweb_version/" $out/${python3Packages.python.sitePackages}/calibreweb/cps/templates/admin.html

  cp -r $cwa_src/cps/static $out/${python3Packages.python.sitePackages}/calibreweb/cps/static
  '';

  pythonImportsCheck = [ "calibreweb" ];

  meta.mainProgram = "calibre-web";
}
