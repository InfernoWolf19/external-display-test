#!/usr/bin/env python3
"""Flat APT repository for Sileo / Zebra (GitHub Pages), with version history.

  aptrepo.py SITE add DEB --run N --sha SHA --subject TEXT --date ISO8601
  aptrepo.py SITE rebuild

SITE is the checkout of the gh-pages branch.  `add` re-versions the .deb as <control version>+<run>.<sha7> (monotonic per CI run, the commit is in the version
string Sileo lists), appends the commit subject to the extended Description, stores it in SITE/debs/ and regenerates Packages{,.gz,.bz2}, Release, index.html and
history.json.  Every version still in debs/ stays in Packages (Sileo lists them under 'Versions'); the newest KEEP versions are kept.
"""
import argparse, bz2, functools, gzip, hashlib, html, json, os, shutil, subprocess, sys, tempfile
from email.utils import formatdate

KEEP = 60
PKG_ARCH = "iphoneos-arm64"


def sh(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k).stdout


def vcmp(a, b):
    if a == b:
        return 0
    return 1 if subprocess.run(["dpkg", "--compare-versions", a, "gt", b]).returncode == 0 else -1


def read_control(path):
    return sh("dpkg-deb", "-I", path, "control")


def field(ctrl, name):
    for ln in ctrl.splitlines():
        if ln.startswith(name + ":"):
            return ln.split(":", 1)[1].strip()
    return None


def digest(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_history(site):
    p = os.path.join(site, "history.json")
    return json.load(open(p)) if os.path.exists(p) else {}


def add(site, deb, run, sha, subject, date):
    work = tempfile.mkdtemp()
    pkgdir = os.path.join(work, "pkg")
    sh("dpkg-deb", "-R", deb, pkgdir)
    cpath = os.path.join(pkgdir, "DEBIAN", "control")
    ctrl = open(cpath).read()
    base = field(ctrl, "Version")
    package = field(ctrl, "Package")
    version = "%s+%s.%s" % (base, run, sha[:7])
    subject = (subject or "").splitlines()[0].strip() if subject else ""
    lines = ctrl.rstrip("\n").split("\n")
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("Version:"):
            ln = "Version: " + version
        out.append(ln)
        if ln.startswith("Description:"):          # extended description: build id + commit name (Sileo shows the description of the selected version)
            while i + 1 < len(lines) and lines[i + 1].startswith(" "):
                i += 1
                out.append(lines[i])
            out.append(" .")
            out.append(" Build %s, commit %s: %s" % (run, sha[:7], subject or "(no subject)"))
        i += 1
    open(cpath, "w").write("\n".join(out) + "\n")
    os.makedirs(os.path.join(site, "debs"), exist_ok=True)
    name = "%s_%s_%s.deb" % (package, version, PKG_ARCH)
    dest = os.path.join(site, "debs", name)
    sh("dpkg-deb", "--root-owner-group", "-Zgzip", "-b", pkgdir, dest)
    shutil.rmtree(work)
    hist = load_history(site)
    hist[version] = {"version": version, "sha": sha, "run": int(run), "subject": subject, "date": date, "file": "debs/" + name}
    json.dump(hist, open(os.path.join(site, "history.json"), "w"), indent=1, sort_keys=True)
    print("added", name)


def rebuild(site):
    ddir = os.path.join(site, "debs")
    os.makedirs(ddir, exist_ok=True)
    entries = []
    for fn in os.listdir(ddir):
        if fn.endswith(".deb"):
            p = os.path.join(ddir, fn)
            ctrl = read_control(p)
            entries.append((field(ctrl, "Version"), fn, p, ctrl))
    entries.sort(key=functools.cmp_to_key(lambda a, b: -vcmp(a[0], b[0])))      # newest first
    hist = load_history(site)
    for v, fn, p, _ in entries[KEEP:]:
        os.remove(p)
        hist.pop(v, None)
    entries = entries[:KEEP]
    json.dump(hist, open(os.path.join(site, "history.json"), "w"), indent=1, sort_keys=True)
    stanzas = []
    for v, fn, p, ctrl in entries:
        s = ctrl.rstrip("\n") + "\n"
        s += "Filename: debs/%s\nSize: %d\nMD5sum: %s\nSHA1: %s\nSHA256: %s\n" % (fn, os.path.getsize(p), digest(p, "md5"), digest(p, "sha1"), digest(p, "sha256"))
        stanzas.append(s)
    packages = ("\n".join(stanzas)).encode()
    files = {"Packages": packages, "Packages.gz": gzip.compress(packages, 9, mtime=0), "Packages.bz2": bz2.compress(packages, 9)}
    for n, data in files.items():
        open(os.path.join(site, n), "wb").write(data)
    rel = ["Origin: infernowolf19", "Label: Backport162", "Suite: stable", "Version: 1.0", "Codename: ios",
           "Architectures: " + PKG_ARCH, "Components: main",
           "Description: Backport162 CI builds (iPadOS 16.2 Stage Manager / external display backport for iPadOS 16.0)",
           "Date: " + formatdate(usegmt=True)]
    for title, algo in (("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")):
        rel.append(title + ":")
        for n, data in files.items():
            rel.append(" %s %d %s" % (hashlib.new(algo, data).hexdigest(), len(data), n))
    open(os.path.join(site, "Release"), "w").write("\n".join(rel) + "\n")
    open(os.path.join(site, ".nojekyll"), "w").write("")
    write_index(site, entries, hist)
    print("repo rebuilt: %d versions" % len(entries))


def write_index(site, entries, hist):
    slug = os.environ.get("GITHUB_REPOSITORY", "InfernoWolf19/external-display-test")
    owner, repo = slug.split("/")
    url = "https://%s.github.io/%s/" % (owner.lower(), repo)
    rows = []
    for v, fn, p, ctrl in entries:
        h = hist.get(v, {})
        sha = h.get("sha", "")
        rows.append("<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td><a href=\"debs/%s\">deb</a></td></tr>" % (
            html.escape(v),
            ("<a href=\"https://github.com/%s/commit/%s\">%s</a>" % (slug, sha, html.escape(sha[:7]))) if sha else "",
            html.escape(h.get("subject", "")), html.escape(fn)))
    page = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Backport162 repo</title><style>body{font:16px -apple-system,system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 1rem}
code{background:#8883;padding:.1em .3em;border-radius:4px}table{border-collapse:collapse;width:100%%}td,th{border-bottom:1px solid #8884;padding:.35rem .5rem;text-align:left;vertical-align:top}</style></head>
<body><h1>Backport162</h1><p>CI builds of the iPadOS 16.2 Stage Manager / external display backport for iPadOS 16.0 (rootless).</p>
<p><a href="sileo://source/%s">Add to Sileo</a> &middot; <a href="zbra://sources/add/%s">Add to Zebra</a> &middot; or add <code>%s</code> manually.</p>
<p>Every build stays listed: long-press <i>Get</i> / <i>Modify</i> in Sileo and pick a version (version = release + CI run + commit).</p>
<table><tr><th>Version</th><th>Commit</th><th>Change</th><th></th></tr>%s</table></body></html>""" % (url, url, url, "\n".join(rows))
    open(os.path.join(site, "index.html"), "w").write(page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("site")
    ap.add_argument("cmd", choices=["add", "rebuild"])
    ap.add_argument("deb", nargs="?")
    ap.add_argument("--run")
    ap.add_argument("--sha")
    ap.add_argument("--subject", default="")
    ap.add_argument("--date", default="")
    a = ap.parse_args()
    if a.cmd == "add":
        if not (a.deb and a.run and a.sha):
            sys.exit("add needs DEB --run --sha")
        add(a.site, a.deb, a.run, a.sha, a.subject, a.date)
    rebuild(a.site)


if __name__ == "__main__":
    main()
