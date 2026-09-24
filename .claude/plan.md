# Plan: Reconcile App Code + Establish Architecture

## Goal
Make `python-hostinfo` the canonical source of app code for all deployment scenarios
(traditional container and bootc). Image builds live in `lab-images`; app development
lives here.

## Context
Three versions of the app exist today:
- `lab-images/hostinfo-app/app/` — most advanced: host-view toggle (container vs host
  OS introspection via `/host/` bind mounts), toggle UI in template
- `python-hostinfo` main — simpler: no toggle, but has `hummingbird` distro detection
  and `/run/.containerenv` container detection that lab-images lacks
- `python-hostinfo` bootc branch — oldest: missing all of the above

`lab-images` is the central image build/publish home. `python-hostinfo` is app-only.

## Constraints
- `lab-images/hostinfo-app/` is live in production — do NOT touch it in this work
- The bootc branch of `python-hostinfo` will be retired once this work lands
- All changes on a new branch (`feature/reconcile-app`) for clean review

## Steps

### Step 1 — Create branch
```
git checkout -b feature/reconcile-app
```

### Step 2 — Reconcile app code on the branch
Base: take lab-images/hostinfo-app/app/ as the source (it is the most advanced).
Apply fixes from current python-hostinfo main that lab-images is missing.

Files to update (copy from lab-images, then patch):

**app.py** — take lab-images version as-is (has `view` parameter, request.args handling)

**helpers.py** — take lab-images version, then:
  - Add `'hummingbird'` to the rpm-based distro list in `get_system_package_version`
  - Add `/run/.containerenv` detection inside the `view='container'` path of `get_os_info`
    (sets `info['system'] = 'Linux (containerized)'`)

**static/main.js** — take lab-images version as-is (has view toggle logic)

**templates/index.html** — take lab-images version as-is (has toggle UI + warning alert)

**static/style.css** — identical, no change needed
**config.json** — identical, no change needed

### Step 3 — Verify no regressions on branch
Check that the app starts cleanly and the /data endpoint works in both view modes.
Local test paths (see Testing section below).

### Step 4 — Commit and push branch
Open PR against main in python-hostinfo for review.

### Step 5 (separate work, after this branch merges)
Create `lab-images/hostinfo-bootc/` using the new CI-clone-at-build-time pattern:
- Containerfile (rhel10/rhel-bootc base) — references app/ that CI provides
- info-app.service, info-app.conf, nginx_connect_flask_sock.te
- GitHub Actions workflow: clone python-hostinfo main → build bootc image
This validates the new architecture before touching the live hostinfo-app.

### Step 6 (later, after bootc pattern is validated in production)
Migrate `lab-images/hostinfo-app/` to clone-at-build-time, removing the local app/ copy.

## Testing
After reconciliation on the branch, local test paths:

### Direct Python run (fastest)
```bash
cd app
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
flask run --host=0.0.0.0 --port=5000   # or: gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
```
Then:
- `curl http://localhost:5000/data` — container view (default)
- `curl http://localhost:5000/data?view=host` — host view (will show /host/ mount missing
  warning since /host/ isn't bound, which is expected and correct)

### Container run (validates the Containerfile still works)
```bash
podman build -t hostinfo-test -f Containerfile .
podman run -d --name hostinfo-test -p 8000:8000 hostinfo-test
curl http://localhost:8000/data | python3 -m json.tool
podman stop hostinfo-test && podman rm hostinfo-test
```

### Container run with host view mounts (validates host view end-to-end)
```bash
podman run -d --name hostinfo-host \
  -p 8000:8000 \
  -v /:/host:ro \
  -e HOST_HOSTNAME=$(hostname) \
  hostinfo-test
curl http://localhost:8000/data?view=host | python3 -m json.tool
podman stop hostinfo-host && podman rm hostinfo-host
```

## What this does NOT do
- Does not change live lab-images/hostinfo-app (left intact)
- Does not delete the python-hostinfo bootc branch (cleanup deferred)
- Does not create lab-images/hostinfo-bootc (separate step)
