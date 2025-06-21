{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  nixosTests,
}:

buildGoModule rec {
  pname = "sftpgo";
  version = "2.7.0-pre1";

  src = fetchFromGitHub {
    owner = "drakkan";
    repo = "sftpgo";
    rev = "fb46c28ff2ca536ea56c15ddd9e8e001abf9a8d0";
    hash = "sha256-jogO8w6fOrmQzCE2JErH9m8P8lyhs48EmIoSyg3wejI=";
  };

  vendorHash = "sha256-gnzIbnt4/uN0RAJmRGek6TEnrWr0s6XrEN6LFPhWmvs=";

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
