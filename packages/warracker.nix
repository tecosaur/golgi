{ lib
, python3Packages
, fetchFromGitHub
}:

python3Packages.buildPythonApplication rec {
  pname = "warracker";
  version = "0.10.1.12";
  pyproject = false;

  src = fetchFromGitHub {
    owner = "sassanix";
    repo  = "Warracker";
    # rev   = version;
    rev = "10d2817ae53423619d5ba31a3969b0252d243922";
    hash  = "sha256-k3KfiQ4skqakyuHcbihWFFn05Xr+e2I0Yj55yHX+SBw=";
  };

  dependencies = with python3Packages; [
    apprise
    apscheduler
    authlib
    babel
    email-validator
    flask
    flask-babel
    flask-bcrypt
    flask-cors
    flask-login
    gevent
    gunicorn
    psycopg2
    pyjwt
    python-dateutil
    requests
  ];

  passthru = {
    python = python3Packages.python;
    pythonPath = python3Packages.makePythonPath dependencies;
  };

  postBuild = ''
  PYTHONPATH=$out/${python3Packages.python.sitePackages}:$PYTHONPATH
  '';

  installPhase = ''
    runHook preInstall

    site="$out/${python3Packages.python.sitePackages}"
    mkdir -p "$site" "$out/share/warracker/static" "$out/bin"

    # Install the Python server code
    cp -r backend "$site/backend"

    # Install static frontend assets (adjust if upstream layout changes)
    cp -r frontend/* "$out/share/warracker/static/"
    cp -r locales "$out/share/warracker/static/"

    # Executable: gunicorn launcher
    cat > "$out/bin/.unwrapped-warracker-gunicorn" <<'EOF'
#!/bin/sh
exec ${python3Packages.gunicorn}/bin/gunicorn "$@" 'backend:create_app()'
EOF
    chmod +x "$out/bin/.unwrapped-warracker-gunicorn"

    # Executable: migrations
    cat > "$out/bin/.unwrapped-warracker-migrate" <<'EOF'
#!/bin/sh
exec ${python3Packages.python.interpreter} -m backend.migrations.apply_migrations "$@"
EOF
    chmod +x "$out/bin/.unwrapped-warracker-migrate"

    for prog in warracker-gunicorn warracker-migrate; do
      makeWrapper "$out/bin/.unwrapped-$prog" "$out/bin/$prog" \
        --prefix PYTHONPATH : "$PYTHONPATH"
    done

    runHook postInstall
  '';

  # Simple import verification.
  pythonImportsCheck = [ "backend" ];

  meta = with lib; {
    description = "Warracker – Warranty tracking Flask application";
    homepage    = "https://github.com/sassanix/Warracker";
    license     = licenses.gpl3Only;
    platforms   = platforms.unix;
    mainProgram = "warracker-gunicorn";
    maintainers = []; # add yourself or others if upstreamed to nixpkgs
  };
}
