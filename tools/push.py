"""推送 AgentPilot 到 GitHub（单公开库方案）。

用法:
  set GH_TOKEN_INPUT=<你的GitHub PAT>
  python tools/push.py

功能:
  1. 创建公开仓库 YoYulyvW/agent-pilot（不存在时）
  2. git init / commit / push 到 main
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

tok = os.environ.get("GH_TOKEN_INPUT")
if not tok:
    print("请先设置环境变量 GH_TOKEN_INPUT")
    sys.exit(1)

OWNER = "YoYulyvW"
REPO = "agent-pilot"
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def api(path, method="GET", body=None):
    url = "https://api.github.com" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "token " + tok)
    req.add_header("User-Agent", "AgentPilot")
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read().decode().strip()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print("API %s %s -> HTTP %s" % (method, path, e.code))
        return None


def ensure_repo():
    r = api("/repos/%s/%s" % (OWNER, REPO))
    if r:
        print("已存在仓库:", REPO, "(private)" if r.get("private") else "(public)")
        return
    r = api("/user/repos", "POST", {"name": REPO, "private": False,
                                    "auto_init": False})
    print("创建公开仓库:", REPO)


def main():
    ensure_repo()

    git = "git"
    if not os.path.isdir(os.path.join(PROJECT_DIR, ".git")):
        subprocess.run([git, "init", "-b", "main"], cwd=PROJECT_DIR, check=True)
    subprocess.run([git, "add", "-A"], cwd=PROJECT_DIR, check=True)
    commit = subprocess.run([git, "diff", "--cached", "--quiet"], cwd=PROJECT_DIR)
    if commit.returncode != 0:
        subprocess.run([git, "commit", "-m", "init: AgentPilot iOS client"],
                       cwd=PROJECT_DIR, check=True)
    remote = subprocess.run([git, "remote", "get-url", "origin"],
                            cwd=PROJECT_DIR, capture_output=True, text=True)
    if remote.returncode != 0:
        subprocess.run([git, "remote", "add", "origin",
                        "https://x-access-token:%s@github.com/%s/%s.git" % (tok, OWNER, REPO)],
                       cwd=PROJECT_DIR, check=True)
    else:
        subprocess.run([git, "remote", "set-url", "origin",
                        "https://x-access-token:%s@github.com/%s/%s.git" % (tok, OWNER, REPO)],
                       cwd=PROJECT_DIR, check=True)
    subprocess.run([git, "push", "-u", "origin", "main"], cwd=PROJECT_DIR, check=True)
    print("完成：已推送到 %s/%s" % (OWNER, REPO))


if __name__ == "__main__":
    main()
