{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  nixosTests,
}:

buildGoModule rec {
  pname = "sftpgo";
  version = "2.7.6-pre1";

  src = fetchFromGitHub {
    owner = "tecosaur";
    repo = "sftpgo";
    rev = "fa2538c25f71b05948a4d67684e9ad8efcddb6d1";
    hash = "sha256-C0U5GGbc9sYc0/nO53fKp2sOTEs6bhkz2/YkiJB4j5I=";
  };

  vendorHash = "sha256-mwFXECEELvE2HlSbssV5GcG8ibXFwLv5EAHaytb7YLQ=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/drakkan/sftpgo/v2/internal/version.commit=${src.rev}"
    "-X github.com/drakkan/sftpgo/v2/internal/version.date=1970-01-01T00:00:00Z"
  ];

  nativeBuildInputs = [ installShellFiles ];

  doCheck = false;

  subPackages = [ "." ];

  postInstall = ''
    $out/bin/sftpgo gen man
    installManPage man/*.1

    installShellCompletion --cmd sftpgo \
      --bash <($out/bin/sftpgo gen completion bash) \
      --zsh <($out/bin/sftpgo gen completion zsh) \
      --fish <($out/bin/sftpgo gen completion fish)

    shareDirectory="$out/share/sftpgo"
    mkdir -p "$shareDirectory"
    cp -r ./{openapi,static,templates} "$shareDirectory"
  '';

  passthru.tests = nixosTests.sftpgo;

  meta = {
    homepage = "https://github.com/drakkan/sftpgo";
    changelog = "https://github.com/drakkan/sftpgo/releases/tag/v${version}";
    description = "Fully featured and highly configurable SFTP server";
    longDescription = ''
      Fully featured and highly configurable SFTP server
      with optional HTTP/S, FTP/S and WebDAV support.
      Several storage backends are supported:
      local filesystem, encrypted local filesystem, S3 (compatible) Object Storage,
      Google Cloud Storage, Azure Blob Storage, SFTP.
    '';
    license = with lib.licenses; [
      agpl3Only
      unfreeRedistributable
    ]; # Software is AGPLv3, web UI is unfree
    maintainers = with lib.maintainers; [ thenonameguy ];
    mainProgram = "sftpgo";
  };
}
