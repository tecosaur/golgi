let
  base = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity";
  golgi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEmWE6y+gkNdOdgooahbgalxguyoPos7dKCAeVzokm/ root@golgi";
  nucleus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOeDXHlRp0k18hSszwUYw+5FiNbPE+XLxRdXSqUUdYOF root@nucleus";
  gbase = [ base golgi ];
  nbase = [ base nucleus ];
  all = [ base golgi nucleus ];
in
{
  # Paired with the `*-hash.txt` digests; both written by `make-oidc.sh`.
  "oidc/beszel-secret.age".publicKeys = gbase;
  "oidc/dawarich-secret.age".publicKeys = nbase;
  "oidc/headplane-secret.age".publicKeys = gbase;
  "oidc/headscale-secret.age".publicKeys = gbase;
  "oidc/immich-secret.age".publicKeys = nbase;
  "oidc/jellyfin-secret.age".publicKeys = nbase;
  "oidc/memos-secret.age".publicKeys = gbase;
  "oidc/paperless-secret.age".publicKeys = nbase;
  "oidc/rustical-secret.age".publicKeys = gbase;
  "oidc/sftpgo-secret.age".publicKeys = nbase;
  "oidc/storyteller-secret.age".publicKeys = nbase;
  "oidc/tandoor-secret.age".publicKeys = nbase;
  "oidc/vikunja-secret.age".publicKeys = gbase;
  "oidc/warracker-secret.age".publicKeys = nbase;
  "oidc/windmill-secret.age".publicKeys = nbase;

  # Set by hand: from a third party, or from a service that alone can mint it.
  "credentials/beszel-token.age" = { publicKeys = all; description = "Beszel hub token"; };
  "credentials/cloudflare-api-env.age" = { publicKeys = all; description = "Cloudflare API token, as CLOUDFLARE_API_TOKEN=..."; };
  "credentials/crowdsec-enroll-key.age" = { publicKeys = all; description = "CrowdSec console enrolment key"; };
  "credentials/fastmail.age" = { publicKeys = all; description = "Fastmail app password, for SMTP"; };
  "credentials/home-assistant-secrets.age" = { publicKeys = nbase; description = "Home Assistant secrets.yaml"; };
  "credentials/mealie-credentials-env.age" = { publicKeys = gbase; description = "Mealie OIDC/SMTP environment"; };
  "credentials/ntfy-webpush-keys-env.age" = { publicKeys = gbase; description = "ntfy web push keys"; };
  "credentials/tailscale-preauth.age" = { publicKeys = all; description = "Tailscale pre-auth key"; };
  "credentials/tandoor-fdc-api-key.age" = { publicKeys = nbase; description = "USDA FoodData Central API key"; };

  "passwords/llm-api-key.age" = { publicKeys = all; description = "Shared secret between the llama-server and its clients"; };
  "passwords/lldap-admin-password.age" = { publicKeys = all; description = "LLDAP admin login, used at its web UI"; };
  "passwords/paperless-admin-password.age" = { publicKeys = nbase; description = "Paperless admin login"; };
  "passwords/sftpgo-admin-password.age" = { publicKeys = nbase; description = "SFTPGo admin login"; };

  # `all`, not `gbase`: every node running the auth stack must hold the same
  # key material to accept the others' tokens.
  "keys/authelia-jwt.age".publicKeys = all;
  "keys/authelia-oidc-hmac.age".publicKeys = all;
  "keys/authelia-oidc-issuer.pem.age".publicKeys = all;
  "keys/authelia-session.age".publicKeys = all;
  "keys/authelia-storage.age".publicKeys = all;
  "keys/lldap-jwt.age".publicKeys = all;
  "keys/lldap-key-seed.age".publicKeys = all;
  "keys/wg-golgi.age".publicKeys = gbase;
  "keys/wg-nucleus.age".publicKeys = nbase;
}
