# TLS terminator and forced HTTPS

How the pilot stack serves HTTPS only (civora-org/civora-platform#168, ADR-011). One reusable overlay, `compose.tls.yml`, puts Caddy in front of the app. It is used by the public demo ([demo-server.md](demo-server.md)) and is the way a municipality's production stack goes public. Without it the stack speaks plain HTTP on port 3000 and must not carry real data.

## What it does

| Concern | How |
|---|---|
| Certificates | Caddy obtains and renews Let's Encrypt certificates for `SITE_ADDRESS` (HTTP-01 on port 80, no DNS API needed). Certificates live in the `caddy-data` volume: keep it, or Let's Encrypt rate limits bite on rebuilds |
| HTTP to HTTPS | Caddy answers every plain request on port 80 with a 308 to the https URL, before the app sees it |
| TLS versions | Caddy's defaults: TLS 1.2 and 1.3, modern cipher suites. This is the "TLS 1.2+" promised in the DPA annex |
| Rails sees https | Caddy forwards `X-Forwarded-Proto`, `-For` and `-Host`. The app trusts them because Rails treats the Docker bridge network (a private range) as a trusted proxy, and because port 3000 is **not published** (`ports: !reset []`), so nothing but Caddy can reach it |
| Forced SSL | `DECIDIM_FORCE_SSL=1` (set by the overlay): Rails redirects any request that is not https, marks session cookies `secure`, and Decidim builds `https://` links |
| HSTS | `Strict-Transport-Security: max-age=31556952; includeSubDomains`, no `preload` (`config/initializers/ssl_options.rb`). One year, covering only subdomains of the stack's own host name. Preload is a one-way commitment for a domain the municipality owns, so it is deliberately off |
| Mail links | Decidim builds mail links from the organization's host and `force_ssl`, so password-reset and notification mails carry `https://<SITE_ADDRESS>/...` |
| Spoofing | Caddy has no `trusted_proxies`, so it discards `X-Forwarded-*` sent by clients and writes its own. A client cannot fake its IP or claim https |
| Health probes | `/up` and `/healthz` are exempt from the redirect. The compose healthcheck, the blackbox exporter and `scripts/deploy.sh` keep probing `http://app:3000/up` on the internal network. The exemption matches the two exact paths only |

The base `compose.yaml` still sets `DECIDIM_FORCE_SSL: "0"` and publishes port 3000: that is the local-development default and is meant to be replaced by the overlay, not edited.

## Variables

In `.env` (template: [`.env.example`](../../.env.example)):

| Variable | Required | Meaning |
|---|---|---|
| `SITE_ADDRESS` | yes | Public host name, no scheme, e.g. `zmluvy.obec.sk` |
| `ACME_EMAIL` | yes | Contact address for Let's Encrypt expiry and policy notices |
| `DECIDIM_ORG_HOST` | yes | Host the organization answers on. **Must equal `SITE_ADDRESS`**, otherwise Decidim does not find the organization and every page is a 404/500 |
| `COMPOSE_FILE` | yes | `compose.yaml:compose.tls.yml` plus the other overlays, e.g. `compose.yaml:compose.tls.yml:compose.observability.yml`. `scripts/deploy.sh`, `smoke_test.sh` and `backup.sh` read it from `.env` |
| `DECIDIM_FORCE_SSL` | no | Set to `"1"` by the overlay; do not put it in `.env` |

Optional when running the scripts from a machine that does not trust the certificate (local rehearsal only): `CURL_OPTS` (extra curl arguments, e.g. `--cacert caddy-root.crt`) and `BASE_URL` (override of the URL the smoke test and the deploy probe use).

## Steps on the real server

1. Point DNS: an `A` record (and `AAAA` if the host has IPv6) for `SITE_ADDRESS` to the server. Wait until `dig +short <host>` shows it.
2. Open ports 80, 443/tcp and 443/udp (HTTP/3) at the provider firewall and in UFW. Caddy needs port 80 even for an HTTPS-only site: Let's Encrypt validates there and the redirect lives there. Remember that Docker publishes ports around UFW, which is why the app's own port is unpublished.
3. Set `SITE_ADDRESS`, `ACME_EMAIL`, `DECIDIM_ORG_HOST` and `COMPOSE_FILE` in `.env`.
4. `scripts/deploy.sh` (backup, `docker compose up -d --build`, smoke test and `/healthz` over `https://<SITE_ADDRESS>`). The smoke test retries for about a minute while the first certificate is issued.
5. Acceptance (the issue's criteria), from any machine:

   ```bash
   curl -sSI http://<host>/                     # 308, Location: https://<host>/
   curl -sSI https://<host>/sk/contracts        # 200, strict-transport-security present
   curl -sS  https://<host>/up                  # 200
   ```

   And open the site in a browser: a padlock with a valid certificate. A password-reset mail must link to `https://<host>/...`.
6. Check the certificate from the outside, for example `openssl s_client -connect <host>:443 -servername <host> </dev/null | openssl x509 -noout -dates -issuer`.

## Monitoring the certificate

The blackbox probes in `observability/prometheus/prometheus.yml` watch the app on the internal network (`http://app:3000/up`, `/healthz`). That covers the app, not Caddy or the certificate. A dead terminator would look like an outage to users and healthy to those probes. Add one public probe per stack, with the real host name, to the `blackbox-up` job targets:

```yaml
      - targets:
          - http://app:3000/up
          - https://<SITE_ADDRESS>/up        # added per stack: checks Caddy and the certificate
```

Prometheus then exposes `probe_ssl_earliest_cert_expiry`, and a rule such as `probe_ssl_earliest_cert_expiry - time() < 14 * 86400` warns two weeks before expiry (Caddy renews at 30 days, so a warning means renewal is failing). The target list is static, so this stays a per-stack edit rather than a shipped default. An external uptime check on the public URL is a good second opinion.

## Local rehearsal (no domain, no Let's Encrypt)

Caddy issues certificates for `*.localhost` names from its own internal CA, so the whole overlay can be exercised on a laptop, in a throwaway compose project that never touches another stack. Ports 80 and 443 must be free on the machine.

```bash
cp .env.example .env     # then set, in this checkout only:
#   COMPOSE_PROJECT_NAME=civora-test-tls   (keeps it away from any other civora-host project)
#   SECRET_KEY_BASE=$(openssl rand -hex 64)   POSTGRES_PASSWORD=$(openssl rand -hex 16)
#   SITE_ADDRESS=civora-tls-test.localhost   DECIDIM_ORG_HOST=civora-tls-test.localhost
#   ACME_EMAIL=ops@example.org   DEMO_MODE=1   (DEMO_MODE writes mail to files, nothing is sent)
#   COMPOSE_FILE=compose.yaml:compose.tls.yml
docker compose up -d --build
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt   # the internal CA

curl -sSI http://civora-tls-test.localhost/sk/contracts                          # 308 to https
curl -sSI --cacert caddy-root.crt https://civora-tls-test.localhost/sk/contracts  # 200 + HSTS
CURL_OPTS="--cacert caddy-root.crt" scripts/smoke_test.sh --keep-up
docker compose down -v
```

`*.localhost` resolves to the loopback address by itself in curl and in browsers; for a browser to trust the page, import `caddy-root.crt` or accept the warning. A browser remembers the HSTS header for a year, so after a rehearsal it refuses plain HTTP on that name: use a different `.localhost` name for the next one.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Certificate never issues, `docker compose logs caddy` shows ACME errors | DNS not pointing here yet; port 80 closed at the provider or in UFW; rate limit after repeated rebuilds without the `caddy-data` volume |
| 404 or error page on every URL over https | `DECIDIM_ORG_HOST` differs from `SITE_ADDRESS` |
| Redirect loop | A second proxy in front of Caddy that terminates TLS without forwarding `X-Forwarded-Proto: https`. Put Caddy first, or add that proxy's address to Caddy's `trusted_proxies` |
| Admin sign-in loops back to the form | Plain-HTTP access with `DECIDIM_FORCE_SSL=1`: the session cookie is `secure` and the browser drops it. Use the https URL |
| App `unhealthy` after enabling the overlay | The image predates `config/initializers/ssl_options.rb`: rebuild (`docker compose up -d --build`) |
