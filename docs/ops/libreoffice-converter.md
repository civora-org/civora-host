# LibreOffice converter

The host image carries LibreOffice Writer so the contracts engine can turn a filled contract-template `.docx` into a PDF (civora-org/civora-platform#211). Toolchain measurements and the decision are in the engine's spike, `docs/spikes/contract-templates-toolchain.md` in `civora-org/decidim-contracts_sk`.

## What is installed

`libreoffice-writer-nogui` and `fonts-liberation`, with `--no-install-recommends`, in the runtime stage of the `Dockerfile` only. Writer is headless (no GUI toolkit). `fonts-liberation` provides metric-compatible stand-ins for Arial, Times New Roman and Courier New, so the PDF keeps the layout of a clerk-authored template. Only Writer is installed: it does not open spreadsheets or presentations. The image grows by about 140 MB compressed; the measured figures are in the PR that added it.

## How the engine calls it

The engine's design (spike section 3; the adapter lands in a later step of #211) is a synchronous call, one conversion per request, no background job and no extra service, with these flags:

```
env -i PATH=/usr/bin:/bin HOME=/tmp/lo-home LANG=C.UTF-8 \
  timeout 60 soffice --headless --norestore \
  -env:UserInstallation=file:///tmp/lo-<uuid> \
  --convert-to pdf --outdir <dir> <input.docx>
```

- **Timeout: 60 seconds**, and the engine kills the whole process group when it fires. A normal conversion takes 0.3 to 0.6 s. `soffice` exits 0 even for garbage input, so the engine also checks that a real `%PDF` file came out.
- **Isolation.** The process runs as the unprivileged `rails` user (uid 1000) with a scrubbed environment (`env -i`, so none of the app's secrets are visible to it). Each run gets its own throwaway profile directory under `/tmp` (`-env:UserInstallation`), deleted afterwards, which avoids the profile lock and means no state survives between conversions. LibreOffice needs only a writable `/tmp`; the image check below proves it for the `rails` user.
- **No network.** Conversion needs no outbound access and the container needs no extra port. The conversion runs offline; restricting the container's egress does not affect it.
- **Memory.** Plan for roughly 200 MB per concurrent conversion on top of the app (a peak of about 170 MB was measured after three sequential runs).

## Operating notes

- A hung or crashed `soffice` shows up as a failed generation in the admin UI, never as a stuck request: the timeout and the process-group kill bound it. If `ps` in the `app` container ever lists `soffice.bin` processes that are minutes old, that is a bug to report with the template involved.
- Do not save a template through LibreOffice once it has merge fields; that is an authoring rule for the engine's template guide (a LibreOffice save rewrites the fields), not an operations step.
- A Gotenberg sidecar is the later option if isolation from the app container matters; it would be a different engine adapter and a new compose service, not a change to this image.

## Verify after a rebuild

```bash
docker compose exec app soffice --version
docker compose exec app sh -c 'cd /tmp && env -i PATH=/usr/bin:/bin HOME=/tmp LANG=C.UTF-8 timeout 60 soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-check --convert-to pdf --outdir /tmp/lo-out <a .docx>'
```
