let
  base = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity";
  golgi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEmWE6y+gkNdOdgooahbgalxguyoPos7dKCAeVzokm/ root@golgi";
  systems = [ base golgi ];
in
{
  "authelia-jwt.age".publicKeys = systems;
  "authelia-oidc-hmac.age".publicKeys = systems;
  "authelia-oidc-issuer.pem.age".publicKeys = systems;
  "authelia-session.age".publicKeys = systems;
  "authelia-storage.age".publicKeys = systems;
  "cloudflare-api-env.age".publicKeys = systems;
  "crowdsec-enroll-key.age".publicKeys = systems;
  "fastmail.age".publicKeys = systems;
  "headscale-oidc-secret.age".publicKeys = systems;
  "headplane-env.age".publicKeys = systems;
  "lldap-admin-password.age".publicKeys = systems;
  "lldap-jwt.age".publicKeys = systems;
  "lldap-key-seed.age".publicKeys = systems;
  "mealie-credentials.env".publicKeys = systems;
  "ntfy-webpush-keys-env.age".publicKeys = systems;
  "postgres-authelia.age".publicKeys = systems;
  "postgres-forgejo.age".publicKeys = systems;
  "tailscale-preauth.age".publicKeys = systems;
}
