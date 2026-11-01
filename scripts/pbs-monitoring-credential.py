#!/usr/bin/env python3
"""Provision a separate read-only PBS monitoring token and store it in Doppler."""
import argparse
import json
import os
import shlex
import subprocess
import sys
import time

USER = "prometheus@pbs"
TOKEN = "victoriametrics"
FULL_ID = f"{USER}!{TOKEN}"
PROJECT = "home-dc-terraform"
CONFIG = "prd"
ID_NAME = "PBS_MONITORING_TOKEN_ID"
SECRET_NAME = "PBS_MONITORING_TOKEN_SECRET"
SSH = ["ssh", "-o", "BatchMode=yes", "pve-00"]
PBS = ["pct", "exec", "4020", "--", "proxmox-backup-manager"]


def command(argv, *, data=None, env=None):
    result = subprocess.run(argv, input=data, text=True, capture_output=True, env=env, timeout=60)
    if result.returncode:
        # Do not emit command output: token generation may contain a one-time secret.
        raise RuntimeError(f"Command failed: {argv[0]} (exit {result.returncode})")
    return result.stdout


def remote(*args):
    return command(SSH + [shlex.join(PBS + list(args))])


def remote_json(*args):
    return json.loads(remote(*args, "--output-format", "json"))


def doppler(env, *args, data=None):
    return command(["doppler", *args, "--project", PROJECT, "--config", CONFIG, "--no-check-version"], data=data, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Create the identity if it does not exist")
    args = parser.parse_args()
    env = os.environ.copy()
    if not env.get("DOPPLER_TOKEN"):
        env["DOPPLER_TOKEN"] = command(["security", "find-generic-password", "-a", env["USER"], "-s", "home-dc-doppler-tf", "-w"]).strip()
    if command(SSH + ["hostname", "-s"]).strip() != "pve-00":
        raise RuntimeError("Unexpected SSH host; refusing to configure PBS")
    versions = remote_json("versions")
    if not versions:
        raise RuntimeError("PBS version check returned no data")
    users = remote_json("user", "list")
    user = next((u for u in users if u.get("userid") == USER), None)
    tokens = remote_json("user", "list-tokens", USER) if user else []
    token = next((t for t in tokens if t.get("tokenid") == FULL_ID), None)
    acls = remote_json("acl", "list")
    names = json.loads(doppler(env, "secrets", "--only-names", "--json"))
    present = {name for name in (ID_NAME, SECRET_NAME) if name in names}
    if len(present) not in (0, 2) or bool(token) != (len(present) == 2):
        raise RuntimeError("PBS token and both Doppler entries must all exist or all be absent; reconcile partial state manually")
    for acl in acls:
        if acl.get("ugid") in (USER, FULL_ID) and (acl.get("path") != "/" or acl.get("roleid") != "Audit"):
            raise RuntimeError("Unexpected direct ACL on PBS monitoring user or token")
    if user and int(user.get("enable", 1)) != 1:
        raise RuntimeError("PBS monitoring user is disabled")
    if token:
        if int(token.get("enable", 1)) != 1 or int(token.get("expire", 0)) <= int(time.time()):
            raise RuntimeError("PBS monitoring token is disabled or expired; rotate deliberately")
        stored_id = doppler(env, "secrets", "get", ID_NAME, "--plain").strip()
        stored_secret = doppler(env, "secrets", "get", SECRET_NAME, "--plain").strip()
        if stored_id != FULL_ID or not stored_secret:
            raise RuntimeError("Stored PBS credential does not match the intended token")
    wanted = (USER, FULL_ID) if token else (USER,)
    missing_acl = [subject for subject in wanted if not any(a.get("ugid") == subject and a.get("path") == "/" and a.get("roleid") == "Audit" and a.get("propagate") is True for a in acls)]
    if not args.apply:
        print(f"PBS credential plan: user={'present' if user else 'create'}, token={'present' if token else 'create'}, missing or non-propagating audit grants={len(missing_acl)}. No changes made.")
        return
    if token and not missing_acl:
        print("PBS monitoring token and audit grants already configured; no changes made.")
        return
    if not user:
        remote("user", "create", USER, "--comment", "Read-only monitoring API token")
    if USER in missing_acl:
        remote("acl", "update", "/", "Audit", "--auth-id", USER, "--propagate", "true")
    if token:
        if FULL_ID in missing_acl:
            remote("acl", "update", "/", "Audit", "--auth-id", FULL_ID, "--propagate", "true")
        print("Restored missing read-only PBS token ACL.")
        return
    try:
        output = remote("user", "generate-token", USER, TOKEN, "--expire", str(int(time.time()) + 31536000))
        start = output.find("{")
        if start < 0:
            raise RuntimeError("PBS did not return a token object")
        created = json.loads(output[start:])
        if created.get("tokenid") != FULL_ID or not created.get("value"):
            raise RuntimeError("PBS returned an unexpected token identity")
        remote("acl", "update", "/", "Audit", "--auth-id", FULL_ID, "--propagate", "true")
        doppler(env, "secrets", "set", SECRET_NAME, "--no-interactive", data=created["value"])
        doppler(env, "secrets", "set", ID_NAME, "--no-interactive", data=FULL_ID)
    except Exception as exc:
        raise RuntimeError("PBS token provisioning did not complete; inspect token and Doppler entry presence and reconcile manually before retrying") from exc
    print("Created privilege-separated, read-only PBS monitoring credential in Doppler.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, subprocess.SubprocessError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
