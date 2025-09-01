{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant
}:

buildHomeAssistantComponent rec {
  owner = "greghesp";
  domain = "bambu_lab";
  version = "2.1.27";

  src = fetchFromGitHub {
    inherit owner;
    repo = "ha-bambulab";
    rev = "ac2a8a77ef91dc45dcdbe18ebc76623808705be9";
    hash = "sha256-PrEFGo5fyQ81Iz+pbOJt7Yp+SfOKdGQsJBk4Y6reYY0=";
  };

  dependencies = with home-assistant.python.pkgs; [ beautifulsoup4 paho-mqtt ];

  meta = with lib; {
    changelog = "https://github.com/greghesp/ha-bambulab/releases/tag/v${version}";
    description = "Custom component for retrieving weather information from the Bureau of Meteorology.";
    homepage = "https://github.com/greghesp/ha-bambulab";
    license = licenses.mit;
  };
}
