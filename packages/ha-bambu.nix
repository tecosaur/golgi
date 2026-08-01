{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant
}:

buildHomeAssistantComponent rec {
  owner = "greghesp";
  domain = "bambu_lab";
  version = "2.2.22";

  src = fetchFromGitHub {
    inherit owner;
    repo = "ha-bambulab";
    tag = "v${version}";
    hash = "sha256-JRJ+tfllDuMrtz+5VQL2l5nkhJQXRoNvsvFnrReSZHE=";
  };

  dependencies = with home-assistant.python3Packages; [ beautifulsoup4 paho-mqtt ];

  meta = with lib; {
    changelog = "https://github.com/greghesp/ha-bambulab/releases/tag/v${version}";
    description = "Custom component for retrieving weather information from the Bureau of Meteorology.";
    homepage = "https://github.com/greghesp/ha-bambulab";
    license = licenses.mit;
  };
}
