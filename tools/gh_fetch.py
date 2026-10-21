#!/usr/bin/env python
"""从 GitHub API (base64) 拉取单个文件，绕过 raw.githubusercontent 在 CN 的不稳定。"""
import base64, json, sys, time, urllib.request, os

def api_get(url):
    req = urllib.request.Request(url, headers={
        'User-Agent': 'curl/8', 'Accept': 'application/vnd.github.raw'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

def fetch(repo, path, out, ref='main'):
    url = f"https://api.github.com/repos/{repo}/contents/{path}?ref={ref}"
    for attempt in range(3):
        try:
            data = api_get(url)
            os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
            open(out, 'wb').write(data)
            print(f"OK   {len(data):8d}  {out}")
            return True
        except Exception as e:
            print(f"  retry{attempt} {path}: {e}")
            time.sleep(2)
    print(f"FAIL {path}")
    return False

if __name__ == '__main__':
    repo = sys.argv[1]
    ref = sys.argv[2]
    base = sys.argv[3]
    for spec in sys.argv[4:]:
        path, out = spec.split('=')
        fetch(repo, path, os.path.join(base, out), ref)
