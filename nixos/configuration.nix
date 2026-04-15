{ config, pkgs, lib, ... }:

/*
  This file is NOT used to build the qcow2 image published by CI.

  CI uses `nixos/image.nix` (via `nixos/flake.nix` → `.#qcow2`) so the image is
  generic and does not bake in per-user SSH keys.

  You can still use this file as a conventional NixOS config if you ever want
  to rebuild the guest from inside Linux (or another Nix-capable environment).
*/

let
  # Update these if you decide to commit the key.
  sshUser = "dockervm";
  authorizedKey = "ssh-ed25519 REPLACE_ME";
in
{
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.hostName = "nix-docker-vm";
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowAgentForwarding = "no";
      AllowTcpForwarding = "no";
      PrintMotd = "no";
    };
  };

  users.users.root.hashedPassword = "!";

  users.users.${sshUser} = {
    isNormalUser = true;
    extraGroups = [ "docker" ];
    openssh.authorizedKeys.keys = [ authorizedKey ];
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };
    };
  };

  environment.systemPackages = with pkgs; [ docker git iproute2 curl ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  system.stateVersion = "25.11";
}

