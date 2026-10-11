# Admin second factor (TOTP)

Implements [civora-org/civora-platform#164](https://github.com/civora-org/civora-platform/issues/164) (ADR-010, option A). Admins and engine role holders must pass a time-based one-time password (TOTP) after their password before any admin surface opens. Public participants and `/system` admins are out of scope.

## Who is affected

`TwoFactor::Policy.required?(user)` is true for:

- organization admins (`admin: true`);
- holders of an engine role, resolved through the engine's own `Decidim::ContractsSk.role_resolver` (so a stored role, a resolver override and the default admin grant all count).

Everyone else (participants, Decidim space role holders who hold no engine role, `Decidim::System::Admin`) signs in exactly as before.

## What the user sees

1. Sign in with e-mail and password, as always.
2. **Not enrolled yet:** the sign-in lands on `/two_factor/enrolment`. The page shows a QR code and the same key as text; the user scans it with any authenticator app and types the six-digit code it shows.
3. A correct code turns the factor on and shows **ten single-use recovery codes, once**. "I have saved them, continue" opens the admin.
4. **Enrolled:** the sign-in lands on `/two_factor/challenge`; a six-digit code (or one recovery code) opens the admin. The user returns to the page they were heading for.
5. Later sign-ins repeat step 4. `/two_factor/recovery_codes` (verified session only) shows how many recovery codes are left and generates a new set, which invalidates the old one.

Any admin path reached without passing the factor in this session (`/admin/*`, `/contracts/admin/*`) redirects to enrolment or the challenge. The public catalogue (`/contracts`), `/account` and the rest of the public site are not gated. The verified flag lives in the session cookie, is bound to the user id, and is cleared by every fresh authentication (password, remember-me cookie, omniauth), so a new sign-in always asks again. The 30 minute inactivity timeout (`DECIDIM_EXPIRE_SESSION_AFTER`) ends the session and with it the flag. Remember-me is withheld from these users.

A password change forced by Decidim (weak admin password) comes first; the second factor follows.

## How it works

| Piece | Where |
|---|---|
| Gate (before-action in every Decidim admin and engine admin controller) | `app/lib/two_factor/gate.rb`, included in `Decidim::Admin::ApplicationController` |
| Post-password redirect | `app/lib/two_factor/sign_in_redirect.rb`, prepended to `Decidim::Devise::SessionsController` |
| No remember-me | `app/lib/two_factor/user_extension.rb`, prepended to `Decidim::User` |
| Engine seam (defence in depth) | `Decidim::ContractsSk.second_factor_satisfied` / `second_factor_redirect_path`, set in `config/initializers/two_factor.rb` |
| Pages | `app/controllers/two_factor/*`, `app/views/two_factor/*` (Decidim public layout and form classes; the few extra rules are scoped under `.two-factor`) |
| Storage | `civora_two_factor_credentials`, `civora_two_factor_recovery_codes`, `civora_two_factor_events` (host-owned; no Decidim table is altered) |
| Throttle | Rack::Attack, 10 POSTs a minute per IP on the code step (`config/initializers/two_factor.rb`); plus a per-user lockout |

Design choices:

- **`rotp` only, not `devise-two-factor`.** `devise-two-factor` replaces Devise's password strategy with a login that carries the code in the same request and stores its columns on `decidim_users`. That means patching `Decidim::User`'s frozen module list and a table Decidim owns. The host keeps the first factor untouched and adds a gate after it, so the core patch surface is three prepended modules and one before-action.
- **Seeds are encrypted at rest** with `Decidim::AttributeEncryptor` (AES-256-GCM, key derived from `SECRET_KEY_BASE`). **Recovery codes are stored only as keyed SHA-256 digests**; the codes are random (60 bits), single use, and each failed attempt counts toward the lockout.
- **A code is accepted once.** The TOTP time step is stored atomically, so replaying a used code, or racing two requests, fails. One 30 second window of clock drift is tolerated either side.
- **Lockout:** five wrong codes (TOTP or recovery) lock the credential for 15 minutes, answered with HTTP 429; the correct code is also refused while locked. The lock writes an audit event.
- **Enrolment cannot be redone with a password alone.** An enrolled user who arrives at `/two_factor/enrolment` is sent to the challenge. Replacing a factor takes an operator reset. Residual risk: an admin who has never enrolled can be enrolled by whoever holds the password first, so enrol every admin **before** the stack is exposed (see the checklist).

## Operations

```bash
# Rollout check: who must use a second factor, and who has not enrolled (no secrets printed)
docker compose exec app bin/rails two_factor:status

# Lost device and lost recovery codes: reset one user (after verifying identity out of band)
docker compose exec app bin/rails two_factor:reset EMAIL=person@example.sk REASON="lost phone, identity confirmed by phone, ticket 42"
# add ORGANIZATION_ID=<id> when the same e-mail exists in several organizations
```

`two_factor:reset` deletes the credential and recovery codes, ends all of the user's sessions and writes one audit row (`kind: reset`, `actor: operator`, the reason, the user id; no e-mail). The user enrols again at the next sign-in. The audit trail is the `civora_two_factor_events` table (kinds: `enrolled`, `recovery_used`, `recovery_regenerated`, `locked`, `reset`); it holds no secrets and no codes:

```bash
docker compose exec db psql -U postgres -d decidim_app_production -c "select created_at, decidim_user_id, kind, actor, reason from civora_two_factor_events order by id desc limit 50"
```

### Rotating `SECRET_KEY_BASE`

The seeds and the recovery-code digests are keyed to `SECRET_KEY_BASE`. After a rotation no enrolled user can pass the challenge (the server answers with an error). Run `bin/rails two_factor:reset_all REASON="secret_key_base rotated"` straight after the rotation; every admin then enrols again. Back up before rotating, like any key change.

### Pilot checklist addition

Before a pilot stack is reachable from the internet: create the admins, then sign in as each one, enrol, and store the recovery codes in the municipality's password manager. `two_factor:status` must report `0 of N not enrolled`.

### Single sign-on

Where a municipality already runs an identity provider that enforces MFA, ADR-010 option B (OmniAuth) is the better control. It is not part of this change; the password path and this gate would still apply to admins until the password path is disabled for them.

## Known gaps

- **`/system` admins** (`Decidim::System::Admin`, a separate model with its own sign-in) are not covered. Follow-up.
- **`/account` and the public site are not gated.** A phished password alone still reaches the account page (change e-mail, change password needs the old one). It does not reach any admin surface.
- **Decidim space role holders** (process admin, collaborator, ...) who hold neither `admin: true` nor an engine role are not required to enrol. Widen `TwoFactor::Policy.required?` if the pilot wants them in.
- **A remember-me cookie issued before this change** keeps authenticating the first factor until it expires; the second factor is asked regardless.
- **Decidim upgrade touch points** to re-verify on every Decidim bump: `Decidim::Admin::ApplicationController` (callbacks), `Decidim::Devise::SessionsController#after_sign_in_path_for` (from `Decidim::DeviseAuthenticationMethods`), the `Decidim::User` `remember_me` accessor and `Decidim::AttributeEncryptor`. The tests in `test/integration/two_factor_flow_test.rb` fail if any of them stops working.
- If upstream Decidim ships native 2FA, remove `app/lib/two_factor`, the three tables and the initializer.
