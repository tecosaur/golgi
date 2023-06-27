{ config, lib, pkgs, ... }:

{
  imports = [ ./z4h.nix ];

  users.defaultUserShell = pkgs.zsh;
  environment.shells = [ pkgs.zsh ];
  environment.systemPackages =
    [ pkgs.exa pkgs.bat pkgs.fd pkgs.ripgrep pkgs.htop ];
  programs.zsh = {
    enable = true;
    shellAliases = {
      l = "exa --long --all --binary --modified --classify --group-directories-first";
      tree = "exa --tree --binary --modified --classify --group-directories-first";
    };
    z4h = {
      enable = true;
      plugins = [ "hlissner/zsh-autopair" ];
      env = {
        POWERLEVEL9K_CONFIG_FILE = "/etc/p10k.zsh";
      };
      envRc = {
        LESS = "--quit-if-one-screen --ignore-case --status-column --LONG-PROMPT --RAW-CONTROL-CHARS --HILITE-UNREAD --tabs=4 --no-init --window=-4";
        BAT_THEME = "ansi";
      };
      autoloads = [ "zmv" ];
      multiLinePrompt = true;
    };
  };
  environment.etc."p10k.zsh".source = ./p10k.zsh;
}
