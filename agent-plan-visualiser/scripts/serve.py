#!/usr/bin/env python3
"""serve.py — local dev server for the agent-plan-visualiser view + analyser endpoints.

Subclass of http.server.SimpleHTTPRequestHandler that:
- Serves the existing static tree (view/, .agent-plan-tracker/) unchanged.
- Adds three local-only endpoints under /api/.
- Binds to 127.0.0.1 only (no external exposure).
- Holds zero credentials, makes zero outbound calls.

Endpoints (T2-analyser §3.4):
  GET  /api/clean-check         — returns {clean: bool, dirty_files: [...]}
  POST /api/save-summary        — appends analysis.live-summary events + writes md files
  POST /api/invalidate-summary  — Phase D will implement; Phase B returns HTTP 501 stub

Usage:
  python3 agent-plan-visualiser/scripts/serve.py [--port 8765] [--host 127.0.0.1]

Replaces `python3 -m http.server 8765` for any flow that needs save-summary. Plain
http.server still works for read-only browsing.
"""
import argparse
import json
import os
import subprocess
import sys
import uuid
from http.server import SimpleHTTPRequestHandler, HTTPServer
from pathlib import Path

import apvlib

# The repo being served is the CALLER's repo (apvlib.repo_root — cwd's
# enclosing repo, falling back to the vendored/dogfood layout). Toolchain
# content (the view itself, schemas) resolves against this script's home.
REPO_ROOT = apvlib.repo_root()
TOOLCHAIN = Path(__file__).resolve().parents[1]
VIEW_DIR = TOOLCHAIN / "view"
DATA_DIR = apvlib.apv_data_dir(REPO_ROOT)
# Repo-root-relative form, used for freeform_path values recorded in events
# (consumed as REPO_ROOT / freeform_path). Falls back to the absolute path if
# APV_DATA_DIR points outside the repo.
try:
    DATA_DIR_PREFIX = str(DATA_DIR.relative_to(REPO_ROOT))
except ValueError:
    DATA_DIR_PREFIX = str(DATA_DIR)
EVENTS = DATA_DIR / "events.jsonl"
SUMMARIES_DIR = DATA_DIR / "summaries"
SCHEMA_PATH = TOOLCHAIN / "schemas/0.2.0/events.schema.json"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def git_clean_check():
    """Return (clean: bool, dirty_files: list[str])."""
    try:
        out = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=str(REPO_ROOT), text=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        return False, [f"git status failed: {e}"]
    if not out.strip():
        return True, []
    return False, [line.rstrip() for line in out.splitlines()]


def load_schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)


def validate_event(event, schema):
    """Returns (ok: bool, error_message: str | None).

    Uses jsonschema if available; else falls back to minimal-shape checks so
    the server still works without the optional dep. The full repack-validate
    pipeline catches schema drift on commit even if jsonschema isn't installed
    on this Python.
    """
    try:
        from jsonschema import validate, ValidationError  # type: ignore
    except ImportError:
        required = {"event_id", "type", "actor", "confidence", "schema_version",
                    "attributes"}
        missing = required - set(event.keys())
        if missing:
            return False, f"missing required keys: {sorted(missing)}"
        return True, None
    try:
        validate(instance=event, schema=schema)
        return True, None
    except ValidationError as e:
        return False, e.message


def latest_summary_for(entity_type, entity_id):
    """Walk events.jsonl; return the most recent analysis.live-summary event
    matching (entity_type, entity_id), OR None.

    Used server-side to compute supersession links authoritatively, instead of
    trusting whatever the browser passed in.
    """
    if not EVENTS.exists():
        return None
    last = None
    with open(EVENTS) as f:
        for raw in f:
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if ev.get("type") != "analysis.live-summary":
                continue
            if ev.get("entity_type") != entity_type or ev.get("entity_id") != entity_id:
                continue
            last = ev
    return last


# ---------------------------------------------------------------------------
# Request handler
# ---------------------------------------------------------------------------

class APTHandler(SimpleHTTPRequestHandler):
    schema_cache = None

    def end_headers(self):
        # Dev review server: disable caching for ALL responses (static assets +
        # JSON). SimpleHTTPRequestHandler sets no Cache-Control, so browsers
        # apply heuristic freshness and serve a stale app.js / projection.json
        # after a rebuild — a normal reload won't revalidate a heuristically
        # fresh subresource, so reviewers silently see old code/data. no-store
        # sidesteps that entirely. This is a local dev tool; caching buys
        # nothing here.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    # --- response helpers -------------------------------------------------

    def _send_json(self, code, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        # Cache-Control: no-store is added centrally in end_headers().
        self.end_headers()
        self.wfile.write(payload)

    def _read_json_body(self):
        length = int(self.headers.get("content-length", "0") or "0")
        if not length:
            return None, "empty body"
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8")), None
        except json.JSONDecodeError as e:
            return None, f"json parse: {e}"

    # --- routing ----------------------------------------------------------

    # Stable routes (T3-historical-projection-ui): the view is toolchain
    # content served from the plugin home; /data/ is the apvlib-resolved
    # data dir; /planning/ is the target repo's plans. Together these make
    # the view work in ANY tracked repo — the app no longer assumes the
    # dogfood layout. Legacy repo-relative URLs still fall through to the
    # SimpleHTTPRequestHandler static tree rooted at REPO_ROOT.

    def _serve_file(self, base: Path, rel: str):
        import mimetypes
        import urllib.parse
        rel = urllib.parse.unquote(rel.split("?", 1)[0])
        base = base.resolve()
        target = (base / rel).resolve()
        # Path-traversal guard: the resolved target must stay inside base.
        if base != target and base not in target.parents:
            return self._send_json(404, {"ok": False, "message": "not found"})
        if not target.is_file():
            return self._send_json(404, {"ok": False, "message": f"not found: {rel}"})
        ctype = mimetypes.guess_type(str(target))[0]
        if not ctype:
            ctype = "application/json" if target.suffix in (".json", ".jsonl") else "text/plain"
        data = target.read_bytes()
        self.send_response(200)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/clean-check":
            clean, dirty = git_clean_check()
            self._send_json(200, {"clean": clean, "dirty_files": dirty})
            return
        if self.path in ("/", "/view", "/view/"):
            self.send_response(302)
            self.send_header("Location", "/view/index.html")
            self.end_headers()
            return
        if self.path.startswith("/view/"):
            return self._serve_file(VIEW_DIR, self.path[len("/view/"):])
        if self.path.startswith("/data/"):
            return self._serve_file(DATA_DIR, self.path[len("/data/"):])
        if self.path.startswith("/planning/"):
            return self._serve_file(REPO_ROOT / "planning", self.path[len("/planning/"):])
        return super().do_GET()

    def do_POST(self):
        if self.path == "/api/save-summary":
            return self._handle_save_summary()
        if self.path == "/api/invalidate-summary":
            return self._handle_invalidate_summary()
        self._send_json(404, {"ok": False, "message": f"unknown endpoint {self.path}"})

    # --- save-summary -----------------------------------------------------

    def _handle_save_summary(self):
        clean, dirty = git_clean_check()
        if not clean:
            self._send_json(409, {
                "ok": False,
                "code": 409,
                "message": "Working tree dirty — commit or stash before saving summary.",
                "dirty_files": dirty,
            })
            return

        body, err = self._read_json_body()
        if err or body is None:
            self._send_json(400, {"ok": False, "message": err or "no body"})
            return

        primary = body.get("event")
        primary_md = body.get("freeform_md", "") or ""
        derived_list = body.get("derived", []) or []
        if not isinstance(primary, dict):
            self._send_json(400, {"ok": False, "message": "missing 'event' (primary)"})
            return

        schema = self._schema()

        # Prepare + validate primary.
        errs = []
        if not self._prepare_event(primary, source_required="primary",
                                   schema=schema, errors_out=errs,
                                   origin_summary_event_id=None):
            self._send_json(422, {
                "ok": False,
                "code": 422,
                "message": "primary event failed validation",
                "errors": errs,
            })
            return

        # Prepare + validate each derived (origin = primary's event_id).
        prepared_derived = []
        for d in derived_list:
            if not isinstance(d, dict):
                self._send_json(400, {"ok": False, "message": "derived item not an object"})
                return
            ev = d.get("event")
            md = d.get("freeform_md", "") or ""
            if not isinstance(ev, dict):
                self._send_json(400, {"ok": False, "message": "derived item missing 'event'"})
                return
            derrs = []
            if not self._prepare_event(ev, source_required="derived",
                                       schema=schema, errors_out=derrs,
                                       origin_summary_event_id=primary["event_id"]):
                self._send_json(422, {
                    "ok": False,
                    "code": 422,
                    "message": f"derived event failed validation for {ev.get('entity_id')}",
                    "errors": derrs,
                })
                return
            prepared_derived.append((ev, md))

        # Write markdown files + append events. Best-effort atomicity: if event
        # append fails after some md files exist, those files become orphans
        # (detectable via a future cache audit; manual cleanup for now).
        SUMMARIES_DIR.mkdir(parents=True, exist_ok=True)

        try:
            self._write_md(primary, primary_md)
            for ev, md in prepared_derived:
                self._write_md(ev, md)

            with open(EVENTS, "a") as f:
                f.write(json.dumps(primary, separators=(",", ":")) + "\n")
                for ev, _ in prepared_derived:
                    f.write(json.dumps(ev, separators=(",", ":")) + "\n")
        except OSError as e:
            self._send_json(500, {
                "ok": False,
                "code": 500,
                "message": f"filesystem write failed: {e}",
            })
            return

        self._send_json(200, {
            "ok": True,
            "primary_event_id": primary["event_id"],
            "derived_event_ids": [ev["event_id"] for ev, _ in prepared_derived],
            "primary_freeform_path": primary["attributes"]["freeform_path"],
        })

    # --- invalidate-summary -----------------------------------------------
    # Phase D — T3-analyser-phase-d-cascade-invalidation.

    def _handle_invalidate_summary(self):
        clean, dirty = git_clean_check()
        if not clean:
            self._send_json(409, {
                "ok": False,
                "code": 409,
                "message": "Working tree dirty — commit or stash before invalidating.",
                "dirty_files": dirty,
            })
            return

        body, err = self._read_json_body()
        if err or body is None:
            self._send_json(400, {"ok": False, "message": err or "no body"})
            return

        target_event_id = body.get("target_event_id")
        reason = body.get("reason", "user-triggered")
        if not target_event_id or not isinstance(target_event_id, str):
            self._send_json(400, {"ok": False, "message": "missing 'target_event_id'"})
            return

        # Scan events.jsonl once: collect all analysis.live-summary +
        # analysis.invalidated events, with their line_no.
        summaries = []
        already_invalidated = set()
        try:
            with open(EVENTS) as f:
                for line_no, raw in enumerate(f, start=1):
                    try:
                        ev = json.loads(raw)
                    except Exception:
                        continue
                    if ev.get("type") == "analysis.live-summary":
                        summaries.append({
                            "event_id": ev["event_id"],
                            "entity_type": ev.get("entity_type"),
                            "entity_id": ev.get("entity_id"),
                            "line_no": line_no,
                            "origin_summary_event_id": ev.get("attributes", {}).get("origin_summary_event_id"),
                            "source": ev.get("attributes", {}).get("source", "primary"),
                        })
                    elif ev.get("type") == "analysis.invalidated":
                        attrs = ev.get("attributes", {})
                        t = attrs.get("target_event_id")
                        if t:
                            already_invalidated.add(t)
                        for c in attrs.get("cascades_to_event_ids", []) or []:
                            already_invalidated.add(c)
        except OSError as e:
            self._send_json(500, {"ok": False, "message": f"events.jsonl read failed: {e}"})
            return

        target = next((s for s in summaries if s["event_id"] == target_event_id), None)
        if target is None:
            self._send_json(404, {
                "ok": False,
                "code": 404,
                "message": f"No analysis.live-summary event found with event_id={target_event_id}",
            })
            return
        if target_event_id in already_invalidated:
            self._send_json(400, {
                "ok": False,
                "code": 400,
                "message": "Target summary is already invalidated.",
            })
            return

        # Load projection.relationships for the spawn-graph cascade rule.
        # We only consider event-sourced spawns (source='event'), not
        # frontmatter-derived edges — those are timeless and would over-cascade.
        try:
            proj = json.loads((DATA_DIR / "projection.json").read_text())
            event_spawn_edges = [
                r for r in proj.get("relationships", [])
                if r.get("type") == "spawns" and r.get("source") == "event"
            ]
        except (OSError, ValueError):
            event_spawn_edges = []

        # Compute cascade per T3 §5 Step 1.
        target_key = f"{target['entity_type']}:{target['entity_id']}"
        # Build a 1-hop spawn-neighbour set for the target's entity.
        spawn_neighbours = set()
        for r in event_spawn_edges:
            if r.get("from") == target_key:
                spawn_neighbours.add(r.get("to"))
            elif r.get("to") == target_key:
                spawn_neighbours.add(r.get("from"))

        cascade = []
        for s in summaries:
            if s["event_id"] == target_event_id:
                continue
            if s["event_id"] in already_invalidated:
                continue  # already invalidated; cascade list excludes
            skey = f"{s['entity_type']}:{s['entity_id']}"
            # (1) Same-entity chain successor
            if skey == target_key and s["line_no"] > target["line_no"]:
                cascade.append(s["event_id"])
                continue
            # (2) Origin chain (derived whose primary IS the target).
            if s["origin_summary_event_id"] == target_event_id:
                cascade.append(s["event_id"])
                continue
            # (3) Cross-entity via spawn graph, after target chronologically.
            if skey in spawn_neighbours and s["line_no"] > target["line_no"]:
                cascade.append(s["event_id"])
                continue
        cascade.sort()

        # Build the invalidation event.
        inv_event = {
            "event_id": str(uuid.uuid4()),
            "type": "analysis.invalidated",
            "entity_type": target["entity_type"],
            "entity_id": target["entity_id"],
            "actor": "al",
            "confidence": "explicit",
            "schema_version": "0.2.0",
            "attributes": {
                "target_event_id": target_event_id,
                "cascades_to_event_ids": cascade,
                "reason": reason or "user-triggered",
            },
        }

        # Validate against schema.
        schema = self._schema()
        ok, err_msg = validate_event(inv_event, schema)
        if not ok:
            self._send_json(500, {
                "ok": False,
                "code": 500,
                "message": "server-built invalidation event failed schema validation",
                "errors": [err_msg],
            })
            return

        # Append.
        try:
            with open(EVENTS, "a") as f:
                f.write(json.dumps(inv_event, separators=(",", ":")) + "\n")
        except OSError as e:
            self._send_json(500, {"ok": False, "message": f"events.jsonl write failed: {e}"})
            return

        self._send_json(200, {
            "ok": True,
            "invalidation_event_id": inv_event["event_id"],
            "target_event_id": target_event_id,
            "cascades_to_event_ids": cascade,
            "reason": reason,
        })

    def _write_md(self, event, md_text):
        path = REPO_ROOT / event["attributes"]["freeform_path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(md_text or "(empty)")

    @classmethod
    def _schema(cls):
        if cls.schema_cache is None:
            cls.schema_cache = load_schema()
        return cls.schema_cache

    def _prepare_event(self, ev, source_required, schema, errors_out,
                       origin_summary_event_id):
        """Mutate event in place: fill scaffolding, derive supersession links,
        compute freeform_path. Validate. Returns True/False; appends to errors_out.

        Supersession rules (T2-analyser §3.13):
          - primary ALWAYS supersedes the most recent summary on E (primary or derived).
          - derived ONLY supersedes a prior derived on E. Never primary.
        Server is authoritative: any client-supplied supersedes_summary_event_id
        pointing at a primary (when source=derived) is overwritten to null.
        """
        # Required scaffolding.
        ev.setdefault("event_id", str(uuid.uuid4()))
        ev.setdefault("type", "analysis.live-summary")
        ev.setdefault("actor", "analyser")
        ev.setdefault("confidence", "explicit")
        ev["schema_version"] = "0.2.0"
        attrs = ev.setdefault("attributes", {})

        # Source — server-enforced.
        attrs["source"] = source_required

        entity_type = ev.get("entity_type")
        entity_id = ev.get("entity_id")
        if not entity_type or not entity_id:
            errors_out.append("missing entity_type/entity_id")
            return False

        # Compute freeform_path from event_id. Always overwrite — client can't
        # be trusted to invent paths that match the storage convention.
        attrs["freeform_path"] = f"{DATA_DIR_PREFIX}/summaries/{entity_id}-{ev['event_id']}.md"

        # origin_summary_event_id — only meaningful for derived.
        if source_required == "derived":
            attrs["origin_summary_event_id"] = origin_summary_event_id
        else:
            attrs["origin_summary_event_id"] = None

        # Supersession — re-derived server-side regardless of what client sent.
        prev = latest_summary_for(entity_type, entity_id)
        if source_required == "primary":
            attrs["supersedes_summary_event_id"] = prev["event_id"] if prev else None
        else:
            # derived: supersede prior derived only; NEVER primary.
            if prev and prev.get("attributes", {}).get("source") == "derived":
                attrs["supersedes_summary_event_id"] = prev["event_id"]
            else:
                attrs["supersedes_summary_event_id"] = None

        # Required structured fields — schema will enforce, but a clearer
        # error for missing fields surfaces faster here.
        structured = attrs.get("structured")
        if not isinstance(structured, dict):
            errors_out.append("missing or non-object 'structured'")
            return False
        for k in ("outstanding", "blocked", "recently_changed"):
            if k not in structured:
                structured[k] = []
        structured.setdefault("next_move", "")

        # model required, default to a sentinel if missing (will fail schema).
        attrs.setdefault("model", "")

        ok, msg = validate_event(ev, schema)
        if not ok:
            errors_out.append(msg)
            return False
        return True


def run(port=8765, host="127.0.0.1"):
    os.chdir(str(REPO_ROOT))
    server = HTTPServer((host, port), APTHandler)
    print(f"serve.py listening on http://{host}:{port}")
    print(f"  view:   http://{host}:{port}/view/index.html (from {VIEW_DIR})")
    print(f"  data:   /data/* -> {DATA_DIR}")
    print(f"  static: serving from {REPO_ROOT}")
    print(f"  endpoints:")
    print(f"    GET  /api/clean-check")
    print(f"    POST /api/save-summary")
    print(f"    POST /api/invalidate-summary  (Phase D — currently HTTP 501 stub)")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
        server.server_close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    run(port=args.port, host=args.host)
