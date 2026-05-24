# `.github/release-iso/` — AurumOS release automation

This directory holds the bits the `release-iso.yml` workflow needs at runtime:

| File | Purpose |
| ---- | ------- |
| `sign.sh` | GPG-signs the built ISO using the key imported from secrets. |
| `release-notes-template.md` | Markdown template populated by the workflow. |
| `README.md` | (You are here.) Maintainer setup notes. |

The full release SOP lives in [`docs/internal/release-process.md`](../../docs/internal/release-process.md).
This file is the **operations** counterpart: how to provision the runner, the
GPG key, and the GitHub secrets so the workflow can succeed.

---

## 1. Self-hosted runner

`release-iso.yml` targets `runs-on: [self-hosted, linux, aurum-builder]`.
GitHub-hosted runners only ship ~14 GB of free disk; an AurumOS ISO build needs
**30+ GB free** and ~2-3 hours wall-clock on a 4-core machine.

### Minimum host spec

- Ubuntu 24.04 LTS (matches Pop!_OS base used by `build.sh`)
- 8+ cores, 16+ GB RAM, 80+ GB free on `/`
- Networking allowed to `iso.pop-os.org`, `archive.ubuntu.com`, `pypi.org`,
  `github.com`, and any vendored mirrors.
- `sudo` without password for the runner user, **scoped** to the build
  commands. Suggested sudoers fragment (`/etc/sudoers.d/aurum-runner`):
  ```
  aurum-runner ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/bin/bash, /usr/bin/debootstrap, /usr/sbin/chroot
  ```

### Provision

```bash
# As root on the host:
useradd -m -s /bin/bash aurum-runner
mkdir -p /opt/actions-runner && cd /opt/actions-runner
curl -fsSLO https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
chown -R aurum-runner:aurum-runner /opt/actions-runner

# Then, as aurum-runner:
./config.sh --url https://github.com/<org>/aurum-os \
            --token <token-from-repo-settings> \
            --labels self-hosted,linux,aurum-builder \
            --unattended
sudo ./svc.sh install aurum-runner
sudo ./svc.sh start
```

Confirm the labels match `release-iso.yml`'s `runs-on` exactly. Re-register
after kernel updates or OS upgrades.

---

## 2. GPG signing key

The workflow signs ISOs with a GPG key whose **private** material is stored in
GitHub repository secrets. **Never commit the private key.**

### Generate (once)

```bash
gpg --batch --quick-generate-key 'AurumOS Release Signing <aurum-os@aurumos.dev>' rsa4096 sign 5y
gpg --armor --export aurum-os@aurumos.dev > aurumos-signing.pub.asc
gpg --armor --export-secret-keys aurum-os@aurumos.dev > aurumos-signing.sec.asc
```

Distribute `aurumos-signing.pub.asc` publicly (commit it under `distro/`,
publish to `keys.openpgp.org`, and link from `release-process.md`).

### Required GitHub secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | Required | What goes in |
| ------ | -------- | ------------ |
| `AURUM_GPG_PRIVATE_KEY` | yes | Full contents of `aurumos-signing.sec.asc` (ASCII-armored). |
| `AURUM_GPG_PASSPHRASE` | optional | Only if the key is passphrase-protected. Recommended. |
| `DISCORD_WEBHOOK` | optional | Discord webhook URL for release announcements. |

The workflow imports the key into an ephemeral `GNUPGHOME` and shreds it after
the job, so the keyring never persists on the runner.

### Sanity-check locally

```bash
# Sign a dummy file using the same script the workflow runs:
AURUM_GPG_KEY_ID=aurum-os@aurumos.dev bash .github/release-iso/sign.sh some-file.iso
gpg --verify some-file.iso.asc some-file.iso
```

---

## 3. Triggering a release

The one-line happy path:

```bash
scripts/aurum-release-helper.sh bump patch    # writes VERSION, commits, tags
git push origin main --tags
```

The workflow opens a **draft** release. A maintainer reviews the assets +
release notes, then clicks **Publish**.

See `docs/internal/release-process.md` for the full checklist (changelog,
benchmark numbers, smoke-boot, rollback).
