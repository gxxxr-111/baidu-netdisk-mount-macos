#!/usr/bin/env python3
"""Create or tune the BaiduNetdisk storage in a running OpenList.

The refresh token is never passed through this script: a new storage gets a
placeholder, and you paste the real token in the OpenList web UI.

Usage: python3 configure-baidu-storage.py [--mount /BaiduNetdisk]
"""
import argparse
import json
import os
import urllib.request

BASE = os.environ.get("OPENLIST_URL", "http://127.0.0.1:5244")
PW_FILE = os.path.expanduser(os.environ.get("OPENLIST_PW_FILE", "~/.config/openlist/admin-password.txt"))

# Tuned for SVIP on a high-latency (overseas) link with a slow uplink.
TUNING = {
    "download_api": "official",          # stable; fast for SVIP with UA pan.baidu.com
    "use_online_api": True,              # token renewed via api.oplist.org
    "low_bandwith_upload_mode": True,    # smallest slices; avoids per-slice timeouts
    "upload_thread": "8",
    "upload_timeout": 300,
}


def call(path, token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    data = json.dumps(body).encode() if body is not None else None
    with urllib.request.urlopen(urllib.request.Request(BASE + path, data, headers)) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mount", default="/BaiduNetdisk")
    args = ap.parse_args()

    pw = open(PW_FILE).read().strip()
    token = call("/api/auth/login", body={"username": "admin", "password": pw})["data"]["token"]
    storages = call("/api/admin/storage/list", token)["data"]["content"]
    existing = next((s for s in storages if s["mount_path"] == args.mount), None)

    if existing:
        s = call(f"/api/admin/storage/get?id={existing['id']}", token)["data"]
        add = json.loads(s["addition"])
        add.update(TUNING)
        s["addition"] = json.dumps(add)
        s["webdav_policy"] = "302_redirect"
        r = call("/api/admin/storage/update", token, s)
        print("updated:", r["code"], r["message"])
        return

    add = {
        "root_folder_path": "/", "order_by": "name", "order_direction": "asc",
        "api_url_address": "https://api.oplist.org/baiduyun/renewapi",
        "client_id": "", "client_secret": "", "custom_crack_ua": "netdisk",
        "refresh_token": "PASTE_REFRESH_TOKEN_HERE",
        "upload_api": "https://d.pcs.baidu.com", "use_dynamic_upload_api": True,
        "custom_upload_part_size": 0, "only_list_video_file": False, **TUNING,
    }
    body = {
        "mount_path": args.mount, "order": 0, "driver": "BaiduNetdisk",
        "cache_expiration": 30, "remark": "", "web_proxy": False,
        "webdav_policy": "302_redirect",   # rclone fetches straight from Baidu
        "down_proxy_url": "", "enable_sign": False, "addition": json.dumps(add),
    }
    r = call("/api/admin/storage/create", token, body)
    # An init error is expected here: the token is still a placeholder.
    print("created:", r["code"], r["message"])
    print(f"Now open {BASE} -> Manage -> Storages -> {args.mount} -> Edit, paste refresh_token, save.")


if __name__ == "__main__":
    main()
