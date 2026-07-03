# Worked example — CI gate adapter (GitHub Actions template)

The gate is one contract (`scripts/gate-check.sh`); *where* it fires is an
installation choice. Local enforcement ships with the plugin (pre-push +
reference-transaction hooks). This template adds a **CI adapter**: gate
every PR targeting main on the PR's head state. It is documentation — the
plugin has no Actions dependency; copy it into the target repo's
`.github/workflows/` and adjust the toolchain step.

Requirements on the runner: `bash`, `git` (full history), `python3` —
gate-check and the integrity composite are stdlib-only.

```yaml
name: apv-gate
on:
  pull_request:
    branches: [main]

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # seal<->commit correspondence needs history

      # The toolchain comes from wherever you have it. Pick ONE:
      #  a) vendored in the repo (nothing to do — point PATHs below at it);
      #  b) a copy of the plugin bundle committed to a tooling repo/artifact
      #     store your org controls, fetched here.
      - name: Fetch APV toolchain
        run: |
          # example (b): unpack a bundle you host
          curl -fsSL "$APV_BUNDLE_URL" -o apv.zip && unzip -q apv.zip
        env:
          APV_BUNDLE_URL: ${{ vars.APV_BUNDLE_URL }}

      - name: Gate the PR head
        run: |
          bash agent-plan-visualiser/scripts/gate-check.sh \
            --repo-root "$PWD" \
            --ref "${{ github.event.pull_request.head.sha }}"
```

The job fails exactly when the gate blocks (exit 1: corruption of the
record — repair append-only, never override) or cannot verify (exit 2).
Warn-level findings print in the job log and pass.

To try the template's core step locally before wiring CI:

```bash
bash "$APV/scripts/gate-check.sh" --repo-root "$PWD" --ref HEAD
```
