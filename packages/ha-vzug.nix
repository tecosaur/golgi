{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant
}:

buildHomeAssistantComponent rec {
  owner = "siku2";
  domain = "vzug";
  version = "0.4.4";

  src = fetchFromGitHub {
    inherit owner;
    repo = "hass-vzug";
    tag = version;
    hash = "sha256-cNu5vL7K220eJUimfFVUlcVxlnzwa4egRw1fRNr2mXo=";
  };

  dependencies = with home-assistant.python.pkgs; [ json-repair ];

  meta = with lib; {
    changelog = "https://github.com/siku2/hass-vzug/releases/tag/v${version}";
    description = "V-ZUG Home Assistant integration.";
    homepage = "https://github.com/siku2/hass-vzug";
    license = licenses.mit;
  };
}
