#!/usr/bin/env python3
import os, re, shlex, shutil, glob

FLAG = "--force-renderer-accessibility"
MARKER = "# generated-by: electron-a11y\n"
OUT = os.path.expanduser("~/.local/share/applications")
SHARED_DIRS = {
    "/usr/lib", "/usr/lib64", "/usr/bin", "/usr/sbin", "/bin", "/sbin",
    "/usr/local/bin", "/usr/local/lib", "/usr/local/sbin", "/opt", "/usr",
}
SYS_DIRS = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]
FLATPAK_APP_DIRS = [
    "/var/lib/flatpak/app",
    os.path.expanduser("~/.local/share/flatpak/app"),
]
FIELD_CODE = re.compile(r"%[a-zA-Z]")


def dir_has_electron(root):
    if not root or not os.path.isdir(root):
        return False
    for base, _dirs, files in os.walk(root):
        if "chrome-sandbox" in files or "libcef.so" in files or any(f.endswith(".asar") for f in files):
            return True
        if base[len(root):].count(os.sep) >= 4:
            _dirs[:] = []
    return False


def resolve_bin(token):
    if os.path.isabs(token):
        return os.path.realpath(token)
    found = shutil.which(token)
    return os.path.realpath(found) if found else None


def native_is_electron(exec_val):
    try:
        toks = shlex.split(exec_val)
    except ValueError:
        return False
    if not toks:
        return False
    binp = resolve_bin(toks[0])
    if not binp or not os.path.exists(binp):
        return False
    name = os.path.basename(binp)
    cands = [
        os.path.dirname(binp),
        f"/usr/lib/{name}",
        f"/opt/{name}",
        os.path.join(os.path.dirname(binp), "..", "lib", name),
    ]
    cands = [os.path.normpath(c) for c in cands]
    cands = [c for c in cands if c not in SHARED_DIRS]
    return any(dir_has_electron(c) for c in cands)


def flatpak_appid(exec_val):
    try:
        toks = shlex.split(exec_val)
    except ValueError:
        return None
    if "flatpak" not in (os.path.basename(toks[0]) if toks else ""):
        return None
    seen_run = False
    for t in toks[1:]:
        if t == "run":
            seen_run = True
            continue
        if seen_run and not t.startswith("-") and not t.startswith("@") and not t.startswith("%"):
            return t
    return None


def flatpak_is_electron(appid):
    for base in FLATPAK_APP_DIRS:
        files = os.path.join(base, appid, "current", "active", "files")
        if dir_has_electron(files):
            return True
    return False


def inject_flag(exec_val):
    if FLAG in exec_val:
        return exec_val
    appid = flatpak_appid(exec_val)
    m = FIELD_CODE.search(exec_val)
    if appid is not None:
        idx = exec_val.find(appid) + len(appid)
        return exec_val[:idx] + " " + FLAG + exec_val[idx:]
    if m:
        return exec_val[:m.start()] + FLAG + " " + exec_val[m.start():]
    return exec_val.rstrip() + " " + FLAG


def is_electron_desktop(exec_lines):
    for ev in exec_lines:
        appid = flatpak_appid(ev)
        if appid and flatpak_is_electron(appid):
            return True
        if appid is None and native_is_electron(ev):
            return True
    return False


def process(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        return None
    exec_vals = [ln[len("Exec="):].rstrip("\n") for ln in lines if ln.startswith("Exec=")]
    if not exec_vals:
        return None
    if not is_electron_desktop(exec_vals):
        return None
    out_lines = []
    changed = False
    for ln in lines:
        if ln.startswith("Exec="):
            val = ln[len("Exec="):].rstrip("\n")
            new = inject_flag(val)
            if new != val:
                changed = True
            out_lines.append("Exec=" + new + "\n")
        else:
            out_lines.append(ln)
    if not changed:
        return None
    return [MARKER] + out_lines


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in glob.glob(os.path.join(OUT, "*.desktop")):
        try:
            with open(path, encoding="utf-8") as f:
                if f.readline() == MARKER:
                    os.remove(path)
        except OSError:
            pass
    written = []
    seen = set()
    for d in SYS_DIRS:
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            base = os.path.basename(path)
            if base in seen:
                continue
            seen.add(base)
            out_lines = process(path)
            if out_lines is None:
                continue
            dest = os.path.join(OUT, base)
            try:
                with open(dest, "w", encoding="utf-8") as f:
                    f.writelines(out_lines)
                written.append(base)
            except OSError:
                pass
    print(f"electron-a11y: patched {len(written)} app(s): {', '.join(written) or '-'}")


if __name__ == "__main__":
    main()
