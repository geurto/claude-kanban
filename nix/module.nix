# System side of claude-kanban on the PC. Imported by the NixOS flake in the
# dev repo, which owns the `claude` user, Remote Control and the idle
# power-off. Everything per-user (settings.json, the claude-kanban@ user unit,
# config.env) is still linked into ~claude by install.sh.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.claude-kanban;
in
{
  options.services.claude-kanban = {
    enable = lib.mkEnableOption "the claude-kanban board runner";

    user = lib.mkOption {
      type = lib.types.str;
      default = "claude";
      description = "Account that runs the board (must already exist).";
    };

    triggerKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAA... serv-board-trigger" ];
      description = ''
        Public keys of serv's `boardsync` user. Each may only start a run-now
        pass; the forced command ignores whatever the client asks to run.
      '';
    };

    nightRun = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start the night pass every day at `nightRun.time`.";
      };
      time = lib.mkOption {
        type = lib.types.str;
        default = "02:00";
        description = ''
          systemd OnCalendar time of day. The PC is powered off when idle, so
          Home Assistant has to Wake-on-LAN it a few minutes before this.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      packages = with pkgs; [
        jq
        yq-go
        rsync
        gh
        git
      ];
      openssh.authorizedKeys.keys = map (
        k: ''restrict,command="systemctl --user start --no-block claude-kanban@now.service" ${k}''
      ) cfg.triggerKeys;
    };

    # A system timer starting a user unit: kept from the S3 design, where
    # WakeSystem needed a system timer. Persistent=false, so booting the PC
    # during the day doesn't replay a missed night pass.
    systemd.services.claude-kanban-night = lib.mkIf cfg.nightRun.enable {
      description = "Start the claude-kanban night pass";
      serviceConfig.Type = "oneshot";
      script = "${pkgs.systemd}/bin/systemctl --user -M ${cfg.user}@ start --no-block claude-kanban@night.service";
    };
    systemd.timers.claude-kanban-night = lib.mkIf cfg.nightRun.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.nightRun.time}";
        Persistent = false;
      };
    };
  };
}
