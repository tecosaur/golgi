{ config, lib, ... }:

# Keep everything a reinstall must recover on the bulk volume: service state
# bound under /data/services, and a few host files copied to /data/host.
#
# Which apps are bound, and how much of each, comes from site.apps:
# an app naming `stateSubdirs` binds only those, leaving anything it derives on
# the system disk. Similarly, `cacheDirs` names subdirectories that should be
# bound to a cache directory.

let
  rootDir = service: setting: fallback:
    let
      value = service.${setting} or fallback;
    in if value == null then null else
    let
      dirs = lib.filter (d: d != "")
        (if builtins.isList value then value else lib.splitString " " value);
      root = lib.foldl'
        (a: b: if lib.hasPrefix (b + "/") a || a == b then b else a)
        (builtins.head dirs) dirs;
      strays = lib.filter (d: d != root && !lib.hasPrefix (root + "/") d) dirs;
    in
      if dirs == [ ] then null
      else if strays == [ ] then root
      else throw ''${setting} names ${
        lib.concatStringsSep " and " (map (d: "\"${d}\"") ([ root ] ++ strays))
      }, which share no parent to bind as one directory'';
  # install.sh restores from a mirror of this table.
  hostFiles = {
    id-maps = [ "/var/lib/nixos/uid-map" "/var/lib/nixos/gid-map" ];
    ssh-host-key = [ "/etc/ssh/ssh_host_ed25519_key" "/etc/ssh/ssh_host_ed25519_key.pub" ];
  };
  # A DynamicUser service keeps its directories under /var/lib/private and
  # /var/cache/private, behind symlinks systemd manages, and systemd chowns
  # them to the uid it allocates at each start. So its mounts go under
  # private/, owned by root until the service takes them.
  dataMountApps =
    lib.filter
      (service: service.stateDir != null)
      (lib.mapAttrsToList
        (name: app:
          let
            cfg = app.serviceConfig;
            dynamic = cfg.DynamicUser or false;
          in
            {
              service = app.service;
              safeName = lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app.name);
              private = dynamic;
              user = if dynamic then "root" else (cfg.User or "root");
              group = if dynamic then "root" else (cfg.Group or "root");
              stateDir = rootDir cfg "StateDirectory"
                (if cfg ? WorkingDirectory
                 then lib.removePrefix "/var/lib/" cfg.WorkingDirectory
                 else null);
              cacheDir = rootDir cfg "CacheDirectory" app.service;
              cacheSubdirs = app.cacheSubdirs;
              stateSubdirs = app.stateSubdirs;
            })
        (lib.filterAttrs
          (_: app:
            app.service != null &&
            app.serviceConfig != { } &&
            app.usesStateDir == true &&
            app.enabled == true &&
            app.host == config.site.server.host)
          config.site.apps));
  backingServices = lib.filterAttrs (name: _: config.services.${name}.enable or false) {
    postgresql = "postgres";
    influxdb2 = "influxdb2";
  };
  dataMounted = dataMountApps ++ lib.mapAttrsToList (name: owner: {
    service = name; safeName = name; stateDir = name; private = false;
    user = owner; group = owner;
    cacheDir = null; cacheSubdirs = [ ]; stateSubdirs = null;
  }) backingServices;
  stateRoot = service: "/var/lib/${lib.optionalString service.private "private/"}${service.stateDir}";
  cacheRoot = service: "/var/cache/${lib.optionalString service.private "private/"}${service.cacheDir}";
  hasPrivate = lib.any (service: service.private) dataMounted;
in
{
  assertions = [
    { assertion = config.fileSystems ? "/data";
      message = "data-mounts binds service state onto /data, which this host does not mount";
    }
  ];

  systemd.tmpfiles.rules =
    [ "d /data/services 0755 root root -" ] ++
    lib.optionals hasPrivate [
      "d /var/lib/private   0700 root root -"
      "d /var/cache/private 0700 root root -"
    ] ++
    lib.flatten (map (service:
      [
        "d /data/services/${service.safeName} 0750 ${service.user} ${service.group} -"
        "d ${stateRoot service}       0755 ${service.user} ${service.group} -"
      ] ++ lib.concatMap
        (d: [
          "d /data/services/${service.safeName}/${d} 0750 ${service.user} ${service.group} -"
          "d ${stateRoot service}/${d}       0750 ${service.user} ${service.group} -"
        ])
        (if service.stateSubdirs == null then [ ] else service.stateSubdirs)
      ++ lib.concatMap
        (d: [
          "d ${cacheRoot service}/${d}        0750 ${service.user} ${service.group} -"
          "d /data/services/${service.safeName}/${d}    0750 ${service.user} ${service.group} -"
        ])
        service.cacheSubdirs)
      dataMounted);

  systemd.mounts = lib.flatten (map
    (service: (map (d: {
      what = "/data/services/${service.safeName}${lib.optionalString (d != "") "/${d}"}";
      where = "${stateRoot service}${lib.optionalString (d != "") "/${d}"}";
      type = "none";
      options = "bind";
      unitConfig.DefaultDependencies = false;
      requires = [ "systemd-tmpfiles-setup.service" "data.mount" ];
      after    = [ "systemd-tmpfiles-setup.service" "data.mount" ];
      wantedBy = [ "multi-user.target" ];
      before   = [ "umount.target" ];
      conflicts = [ "umount.target" ];
    }) (if service.stateSubdirs == null then [ "" ] else service.stateSubdirs))
    ++ (map (d: {
      what = "${cacheRoot service}/${d}";
      where = "${stateRoot service}/${d}";
      type = "none";
      options = "bind";
      unitConfig.DefaultDependencies = false;
      requires = [ "systemd-tmpfiles-setup.service" "data.mount" ];
      after    = [ "systemd-tmpfiles-setup.service" "data.mount" ];
      wantedBy = [ "multi-user.target" ];
      before   = [ "umount.target" ];
      conflicts = [ "umount.target" ];
    }) service.cacheSubdirs))
    dataMounted);

  systemd.services = lib.listToAttrs (map
    (service: {
      name = service.service;
      value.unitConfig.RequiresMountsFor =
        (if service.stateSubdirs == null
         then [ (stateRoot service) ]
         else map (d: "${stateRoot service}/${d}") service.stateSubdirs)
        ++ map (d: "${stateRoot service}/${d}") service.cacheSubdirs;
    })
    dataMounted);

  # After `users` so fresh ids are captured.
  system.activationScripts.persist-host-state = {
    deps = [ "users" ];
    text = ''
      host_dir=/data/host
      persist_host_file() { # group path
        local dest="$host_dir/$1/$(basename "$2")"
        [ -e "$2" ] || return 0
        mkdir -p "$host_dir/$1" && cp -p "$2" "$dest.tmp" && mv -f "$dest.tmp" "$dest" ||
          echo "persist-host-state: could not persist $2" >&2
      }
      if mountpoint -q /data; then
        mkdir -p -m 0700 "$host_dir"
        ${lib.concatMapAttrsStringSep "\n  " (group: lib.concatMapStringsSep "\n  " (path: "persist_host_file ${group} ${path}")) hostFiles}
      else
        echo "persist-host-state: /data is not mounted, host files not persisted" >&2
      fi
    '';
  };
}
