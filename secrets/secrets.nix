let
  base = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity";
  golgi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEmWE6y+gkNdOdgooahbgalxguyoPos7dKCAeVzokm/ root@golgi";
  nucleus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOeDXHlRp0k18hSszwUYw+5FiNbPE+XLxRdXSqUUdYOF root@nucleus";
  gbase = [ base golgi ];
  nbase = [ base nucleus ];
  all = [ base golgi nucleus ];
in
{
  "authelia-jwt.age".publicKeys = gbase;
  "authelia-oidc-hmac.age".publicKeys = gbase;
  "authelia-oidc-issuer.pem.age".publicKeys = gbase;
  "authelia-session.age".publicKeys = gbase;
  "authelia-storage.age".publicKeys = gbase;
  "cloudflare-api-env.age".publicKeys = all;
  "crowdsec-enroll-key.age".publicKeys = all;
  "fastmail.age".publicKeys = all;
  "headscale-oidc-secret.age".publicKeys = gbase;
  "headplane-env.age".publicKeys = gbase;
  "immich-oidc-secret.age".publicKeys = nbase;
  "lldap-admin-password.age".publicKeys = gbase;
  "lldap-jwt.age".publicKeys = gbase;
  "lldap-key-seed.age".publicKeys = gbase;
  "mealie-credentials-env.age".publicKeys = gbase;
  "memos-oidc-secret.age".publicKeys = gbase;
  "ntfy-webpush-keys-env.age".publicKeys = gbase;
  "postgres-authelia.age".publicKeys = gbase;
  "postgres-forgejo.age".publicKeys = gbase;
  "sftpgo-env.age".publicKeys = nbase;
  "sftpgo-oidc-secret.age".publicKeys = nbase;
  "tailscale-preauth.age".publicKeys = all;
  "vikunja-oidc.age".publicKeys = gbase;
}
