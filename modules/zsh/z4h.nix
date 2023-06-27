{ config, lib, options, pkgs, ... }:

with lib;

let
  cfg = config.programs.zsh.z4h;
  package = (pkgs.callPackage ./z4h-package.nix {
    plugins = cfg.plugins;
  });
in
{
  options = {
    programs.zsh.z4h = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc "Enable zsh4humans.";
      };
      plugins = mkOption {
        type = types.listOf(types.str);
        default = [];
        description = lib.mdDoc "List of zsh plugins.";
      };
      path = mkOption {
        type = types.str;
        default = "/var/lib/zsh";
        description = lib.mdDoc "Path to the zsh4humans state dir.";
      };
      histFile = mkOption {
        type = types.str;
        default = "${cfg.path}/history";
        description = lib.mdDoc "Path of the history file to use.";
      };
      env = mkOption {
        type = types.attrs;
        default = { };
        description = lib.mdDoc "Environment variables applied in `.zshenv`.";
      };
      envRc = mkOption {
        type = types.attrs;
        default = { };
        description = lib.mdDoc "Environment variables applied in `.zshrc`.";
      };
      multiLinePrompt = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc "Indicate whether the shell prompt is multi-line.";
      };
      autoloads = mkOption {
        type = types.listOf(types.str);
        default = [];
        description = lib.mdDoc "List of functions to autoload.";
      };
      zstyles = mkOption {
        type = types.str;
        default = ''
        zstyle ':z4h:'                auto-update            'no'
        zstyle ':z4h:bindkey'         keyboard               'pc'
        zstyle ':z4h:'                start-tmux             'no'
        zstyle ':z4h:'                term-shell-integration 'yes'
        zstyle ':z4h:autosuggestions' forward-char           'accept'
        zstyle ':z4h:fzf-complete'    recurse-dirs           'yes'
        zstyle ':z4h:*'               fzf-flags --color=hl:13,hl+:13
        '';
      };
      zstylesExtra = mkOption {
        type = types.str;
        default = "";
      };
      keybindings = mkOption {
        type = types.str;
        default = ''
        z4h bindkey z4h-backward-kill-word  Ctrl+Backspace     Ctrl+H
        z4h bindkey z4h-backward-kill-zword Ctrl+Alt+Backspace
        z4h bindkey undo Ctrl+/ Shift+Tab  # undo the last command line change
        z4h bindkey redo Alt+/             # redo the last undone command line change
        z4h bindkey z4h-cd-back    Alt+Left   # cd into the previous directory
        z4h bindkey z4h-cd-forward Alt+Right  # cd into the next directory
        z4h bindkey z4h-cd-up      Alt+Up     # cd into the parent directory
        z4h bindkey z4h-cd-down    Alt+Down   # cd into a child directory
        # Make the transient prompt work consistently when closing an SSH connection.
        z4h bindkey z4h-eof Ctrl+D
        setopt ignore_eof
        '';
      };
      keybindingsExtra = mkOption {
        type = types.str;
        default = "";
      };
      mdFunction = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc "Define `mkdir` + `cd` function `md`.";
      };
      extraInit = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.zsh = {
      # Interpolated config
      histSize = 50000;
      histFile = "/var/lib/zsh/history";
      enableCompletion = false; # We take care of this manually.
      # .zshenv body
      shellInit = concatStringsSep "\n" [
        ''
        if [ -n "''${ZSH_VERSION-}" ]; then
          HISTFILE=${cfg.histFile}
        ''
        (concatStringsSep "\n"
          (lib.attrsets.mapAttrsToList
            (k: v: "  export ${k}=${v}")
            cfg.env))
        ''
          zsh-newuser-install() { source /etc/zshrc }
          : ''${ZDOTDIR:=~}
          setopt no_global_rcs
          [[ -o no_interactive && -z "''${Z4H_BOOTSTRAPPING-}" ]] && return
          setopt no_rcs
          unset Z4H_BOOTSTRAPPING
        fi

        # Plain prompt for emacs tramp sessions, and no further setup.
        [[ $TERM == "dumb" ]] && unsetopt zle && PS1='> ' && return

        Z4H_URL="https://raw.githubusercontent.com/romkatv/zsh4humans/v5"
        : ''${Z4H:="${cfg.path}"}
        umask o-w
        . "$Z4H"/z4h.zsh || return
        setopt rcs
        ''
      ];
      # .zshrc body
      promptInit = concatStringsSep "\n" [
        "[[ $TERM == \"dumb\" ]] && unsetopt zle && PS1='> ' && return"
        cfg.zstyles
        cfg.zstylesExtra
        (lib.strings.concatMapStringsSep "\n"
          (plg: "z4h install " + plg) cfg.plugins)
        "z4h init || return"
        (concatStringsSep "\n"
          (lib.attrsets.mapAttrsToList
            (k: v: "export ${k}=${v}")
            cfg.env))
        (lib.strings.concatMapStringsSep "\n"
          (plg: "z4h load " + plg) cfg.plugins)
        (lib.strings.concatMapStringsSep "\n"
          (func: "autoload -Uz " + func) cfg.autoloads)
        cfg.keybindings
        cfg.keybindingsExtra
        (if cfg.multiLinePrompt then
        "POSTEDIT=$'\n\n[2A'" else "")
        (if cfg.mdFunction then
        ''
        function md() { [[ $# == 1 ]] && mkdir -p -- "$1" && cd -- "$1" }
        compdef _directories md
        '' else "")
        cfg.extraInit
        "alias ls=\"\${aliases[ls]:-ls} -A\""
        ''
        setopt glob_dots     # no special treatment for file names with a leading dot
        setopt no_auto_menu  # require an extra TAB press to open the completion menu
        ''
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.path} 0755 root wheel"
      "d ${cfg.path}/tmp 0777 root wheel"
      "d ${cfg.path}/cache 0777 root wheel"
      "d ${cfg.path}/stickycache 0777 root wheel"
      "f ${cfg.histFile} 0666 root wheel"
    ] ++ (map
      (stub: "L+ ${cfg.path}/${stub} - - - - ${package}/share/z4h/${stub}")
      (["bin" "fn" "fzf" "powerlevel10k" "systemd"
        "terminfo" "zsh4humans" "zsh-autosuggestions"
        "zsh-completions" "zsh-history-substring-search"
        "zsh-syntax-highlighting" "z4h.zsh" "z4h.zsh.zwc"]
      ++ (lists.unique (map head (map (splitString "/") cfg.plugins)))));
  };
}
