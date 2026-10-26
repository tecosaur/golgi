{ lib
, buildGoModule
, fetchFromGitea
}:

buildGoModule {
  pname = "dns-pooler";
  version = "0.1.0-unstable-2026-10-26";

  src = fetchFromGitea {
    domain = "code.tecosaur.net";
    owner = "tec";
    repo = "dns-pooler";
    rev = "616434db0cd6562032826ca97b4a1f87a523e166";
    hash = "sha256-XqFApAX/TpjZYJ/+xn6rL3gBdT0mFbZD7jgDURyvsdc=";
  };

  vendorHash = "sha256-D8rsQO3nO56DbNKTGnV8rA7trBFKRPqCptB4S+uUQ04=";

  subPackages = [ "cmd/dns-pooler" ];

  # The whole suite, simulation included, rather than only what
  # subPackages builds.
  checkPhase = ''
    runHook preCheck
    go test ./...
    runHook postCheck
  '';

  meta = {
    description = "Keeps a DNS zone's pools matching the hosts able to serve them";
    homepage = "https://code.tecosaur.net/tec/dns-pooler";
    mainProgram = "dns-pooler";
    platforms = lib.platforms.linux;
  };
}
