#!/usr/bin/env python3
"""
replace_mgmt.py — Portable mgmt-subnet rewriter (macOS-safe)
- Rewrites 172.30.0.0/24 -> 172.30.0.0/24 (configurable)
- Rewrites host IPs 192.168.0.{1,2,11,12} -> 172.30.0.{1,2,11,12} (configurable)
- Dry-run by default; --apply to write changes with .bak backups
"""
import argparse, pathlib, re, shutil, sys

SKIP_DIRS = {'.git', '.venv', 'venv', '__pycache__', 'node_modules', '.idea'}
TEXT_EXTS = {'.txt','.md','.yaml','.yml','.cfg','.conf','.ini','.py','.sh','.bash','.zsh','.json','.toml'}

def is_text_file(p: pathlib.Path) -> bool:
    if p.suffix.lower() in TEXT_EXTS:
        return True
    try:
        b = p.read_bytes()[:4096]
        return b'\x00' not in b
    except Exception:
        return False

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--old-net", default="172.30.0.0/24")
    ap.add_argument("--new-net", default="172.30.0.0/24")
    ap.add_argument("--old-base", default="192.168.0")
    ap.add_argument("--new-base", default="172.30.0")
    ap.add_argument("--hosts", default="1,2,11,12")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    hosts = [h.strip() for h in args.hosts.split(",") if h.strip()]
    subnet_re = re.compile(re.escape(args.old_net))
    host_rules = [(re.compile(rf"\b{re.escape(args.old_base)}\.{re.escape(h)}\b"), f"{args.new_base}.{h}") for h in hosts]

    planned = []
    for p in root.rglob("*"):
        if p.is_dir():
            if p.name.startswith(".") or p.name in SKIP_DIRS:
                continue
            continue
        if not is_text_file(p):
            continue
        try:
            text = p.read_text(errors="ignore")
        except Exception:
            continue
        if (args.old_net not in text) and not any(f"{args.old_base}.{h}" in text for h in hosts):
            continue

        new = subnet_re.sub(args.new_net, text)
        for rx, rep in host_rules:
            new = rx.sub(rep, new)

        if new != text:
            planned.append(p)
            if args.apply:
                bak = p.with_suffix(p.suffix + ".bak")
                if not bak.exists():
                    try: shutil.copy2(p, bak)
                    except Exception: shutil.copy(p, bak)
                p.write_text(new)

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[{mode}] root={root} old_net={args.old_net} new_net={args.new_net} old_base={args.old_base} new_base={args.new_base} hosts={hosts}")
    print(f"[{mode}] files to change: {len(planned)}")
    for p in planned:
        print(" -", p.relative_to(root))

if __name__ == "__main__":
    sys.exit(main())
