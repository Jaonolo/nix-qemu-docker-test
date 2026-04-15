{ config, pkgs, lib, ... }:

let
  # Keep the image generic; per-machine SSH keys come from cloud-init seed ISO.
  sshUser = "dockervm";
in
{
  imports = [
    # Adds sane defaults for QEMU guests.
    (pkgs.path + "/nixos/modules/profiles/qemu-guest.nix")
  ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.hostName = "nix-docker-vm";
  networking.useDHCP = true;

  # QEMU guest agent for better host/guest integration (optional but useful).
  services.qemuGuest.enable = true;

  # Cloud-init drives first-boot user setup and authorized keys via NoCloud seed ISO.
  services.cloud-init.enable = true;

  # SSH: locked down; cloud-init provides keys.
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

  # Precreate the intended user; cloud-init can still manage authorized keys.
  users.users.${sshUser} = {
    isNormalUser = true;
    extraGroups = [ "docker" ];
  };

  # Docker Engine (no TCP listener).
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };
    };
  };

  # Separate docker data disk mounted at /var/lib/docker.
  # We expect a second virtio disk (vdb). We format it once if empty, then mount by label.
  systemd.services.init-docker-disk = {
    description = "Initialize docker data disk if needed";
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail
      DEV=/dev/vdb
      if [ ! -b "$DEV" ]; then
        exit 0
      fi
      if ${pkgs.util-linux}/bin/blkid "$DEV" >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F -L docker-data "$DEV"
    '';
  };

  fileSystems."/var/lib/docker" = {
    device = "/dev/disk/by-label/docker-data";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  # Minimal tooling; keep image light.
  environment.systemPackages = with pkgs; [
    util-linux
    e2fsprogs
    docker
    git
    curl
    iproute2
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  system.stateVersion = "25.11";
}

