{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant
}:

buildHomeAssistantComponent rec {
  owner = "bremor";
  domain = "bureau_of_meteorology";
  version = "1.3.6";

  src = fetchFromGitHub {
    inherit owner;
    repo = "bureau_of_meteorology";
    tag = version;
    hash = "sha256-TJ0SLwYVYVdcWGhEUHwpdtk6RRnIwvXQRedW8GubYRM=";
  };

  dependencies = with home-assistant.python.pkgs; [ iso8601 ];

  meta = with lib; {
    changelog = "https://github.com/bremor/bureau_of_meteorology/releases/tag/v${version}";
    description = "Custom component for retrieving weather information from the Bureau of Meteorology.";
    homepage = "https://github.com/bremor/bureau_of_meteorology";
    license = licenses.mit;
  };
}
