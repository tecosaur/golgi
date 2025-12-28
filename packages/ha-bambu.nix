{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant
}:

buildHomeAssistantComponent rec {
  owner = "greghesp";
  domain = "bambu_lab";
  version = "2.2.17";

  src = fetchFromGitHub {
    inherit owner;
    repo = "ha-bambulab";
    tag = "v${version}";
    hash = "sha256-0gAOCs/8U82eOK04mmWs6QqQR1os1eejwvF+pr7U/9c=";
  };

  dependencies = with home-assistant.python.pkgs; [ beautifulsoup4 paho-mqtt ];

  meta = with lib; {
    changelog = "https://github.com/greghesp/ha-bambulab/releases/tag/v${version}";
    description = "Custom component for retrieving weather information from the Bureau of Meteorology.";
    homepage = "https://github.com/greghesp/ha-bambulab";
    license = licenses.mit;
  };
}
