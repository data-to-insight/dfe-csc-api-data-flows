#!/usr/bin/env python3
#chmod +x admin/dev-loc_counter.py

# admin/dev-loc_counter.py /workspaces/dfe-csc-api-data-flows/

"""
loc_counter.py
Counts lines across a project, split by Python, Bash, PowerShell, SQL, YAML, and non-code Markdown lines.
Markdown count excludes fenced code blocks by default.
Jupyter notebooks are parsed, code cells contribute to Python, markdown cells contribute to Markdown non-code.
The unique file count accounts for files only once, per bucket file counts are still shown per category.

Usage examples
  python loc_counter.py                      # scan current folder
  python loc_counter.py /path/to/repo        # scan specific root
  python loc_counter.py -e .git venv site    # exclude common folders
  python loc_counter.py -v --by-file         # verbose summary and per file breakdown
  python loc_counter.py --include-blank      # include blank lines in counts
  python loc_counter.py --include-comments   # include comment only lines in code counts
  python loc_counter.py --out json report.json

Notes
  Bash includes .sh, .bash, .zsh, .ksh, plus files with a shell shebang.
  PowerShell includes .ps1, .psm1, .psd1.
  Python includes .py, plus files with a python shebang, and code cells in .ipynb.
  SQL includes .sql.
  YAML includes .yml and .yaml.
  Markdown includes .md, .markdown, .mdx, plus markdown cells in .ipynb, counted as non-code prose lines.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple, Set

# File type buckets
PY_EXTS = {".py"}
BASH_EXTS = {".sh", ".bash", ".zsh", ".ksh"}
PS_EXTS = {".ps1", ".psm1", ".psd1"}
SQL_EXTS = {".sql"}
YAML_EXTS = {".yml", ".yaml"}
MD_EXTS = {".md", ".markdown", ".mdx"}
IPYNB_EXTS = {".ipynb"}

DEFAULT_EXCLUDES = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "venv",
    "env",
    ".ipynb_checkpoints",
    "node_modules",
    "dist",
    "build",
    "site",
    ".next",
    ".cache",
    ".DS_Store",
}

@dataclass
class Counts:
    files: int = 0
    lines: int = 0

    def add_file(self, n: int) -> None:
        self.files += 1
        self.lines += n

@dataclass
class Totals:
    python: Counts = field(default_factory=Counts)
    bash: Counts = field(default_factory=Counts)
    powershell: Counts = field(default_factory=Counts)
    sql: Counts = field(default_factory=Counts)
    yaml: Counts = field(default_factory=Counts)
    markdown_noncode: Counts = field(default_factory=Counts)
    unique_files: Set[str] = field(default_factory=set)

    def as_dict(self) -> Dict[str, Dict[str, int]]:
        return {
            "python": {"files": self.python.files, "lines": self.python.lines},
            "bash": {"files": self.bash.files, "lines": self.bash.lines},
            "powershell": {"files": self.powershell.files, "lines": self.powershell.lines},
            "sql": {"files": self.sql.files, "lines": self.sql.lines},
            "yaml": {"files": self.yaml.files, "lines": self.yaml.lines},
            "markdown_noncode": {"files": self.markdown_noncode.files, "lines": self.markdown_noncode.lines},
            "all": {
                "files": len(self.unique_files),
                "lines": self.python.lines + self.bash.lines + self.powershell.lines + self.sql.lines + self.yaml.lines + self.markdown_noncode.lines,
            },
        }

def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()

def iter_lines(path: str) -> Iterable[str]:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            yield line

def has_shebang(path: str, token: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            first = f.readline().strip()
    except Exception:
        return False
    return first.startswith("#!") and token in first

def classify_file(path: str) -> Optional[str]:
    """Return coarse type or None if not tracked, .ipynb is returned as 'ipynb' for special handling."""
    _, ext = os.path.splitext(path.lower())
    if ext in PY_EXTS or has_shebang(path, "python"):
        return "python"
    if ext in BASH_EXTS or has_shebang(path, "sh") or has_shebang(path, "bash") or has_shebang(path, "zsh") or has_shebang(path, "ksh"):
        return "bash"
    if ext in PS_EXTS:
        return "powershell"
    if ext in SQL_EXTS:
        return "sql"
    if ext in YAML_EXTS:
        return "yaml"
    if ext in MD_EXTS:
        return "markdown_noncode"
    if ext in IPYNB_EXTS:
        return "ipynb"
    return None

def count_python_lines_from_text(text: str, include_blank: bool, include_comments: bool) -> int:
    n = 0
    for line in text.splitlines():
        s = line.strip()
        if not s:
            if include_blank:
                n += 1
            continue
        if not include_comments and s.startswith("#"):
            if s.startswith("#!"):
                n += 1
            continue
        n += 1
    return n

def count_python_lines(path: str, include_blank: bool, include_comments: bool) -> int:
    n = 0
    for line in iter_lines(path):
        s = line.strip()
        if not s:
            if include_blank:
                n += 1
            continue
        if not include_comments and s.startswith("#"):
            if s.startswith("#!"):
                n += 1
            continue
        n += 1
    return n

def count_bash_lines(path: str, include_blank: bool, include_comments: bool) -> int:
    n = 0
    for line in iter_lines(path):
        s = line.strip()
        if not s:
            if include_blank:
                n += 1
            continue
        if not include_comments and s.startswith("#") and not s.startswith("#!"):
            continue
        n += 1
    return n

def strip_ps_block_comments(text: str) -> str:
    # Remove PowerShell block comments <# ... #>
    return re.sub(r"<#.*?#>", "", text, flags=re.S)

def count_powershell_lines(path: str, include_blank: bool, include_comments: bool) -> int:
    text = read_text(path)
    if not include_comments:
        text = strip_ps_block_comments(text)
    n = 0
    for line in text.splitlines():
        s = line.strip()
        if not s:
            if include_blank:
                n += 1
            continue
        if not include_comments and s.startswith("#"):
            continue
        n += 1
    return n

def strip_sql_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"--.*?$", "", text, flags=re.M)
    return text

def count_sql_lines(path: str, include_blank: bool, include_comments: bool) -> int:
    if include_comments:
        lines = [ln.rstrip("\n") for ln in iter_lines(path)]
        if include_blank:
            return len(lines)
        return sum(1 for ln in lines if ln.strip())
    else:
        text = read_text(path)
        text = strip_sql_comments(text)
        lines = [ln.rstrip("\n") for ln in text.splitlines()]
        if include_blank:
            return len(lines)
        return sum(1 for ln in lines if ln.strip())

FENCE_RE = re.compile(r"^(```+|~~~+)")

def count_markdown_text_noncode_lines(text: str, include_blank: bool) -> int:
    n = 0
    in_fence = False
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        stripped = line.strip()
        if FENCE_RE.match(stripped):
            in_fence = not in_fence
            continue
        if not in_fence:
            if not stripped:
                if include_blank:
                    n += 1
                continue
            if line.startswith("    ") or line.startswith("\t"):
                continue
            n += 1
    return n

def count_markdown_noncode_lines(path: str, include_blank: bool) -> int:
    text = read_text(path)
    return count_markdown_text_noncode_lines(text, include_blank)

def count_yaml_lines(path: str, include_blank: bool, include_comments: bool) -> int:
    n = 0
    for line in iter_lines(path):
        s = line.strip()
        if not s:
            if include_blank:
                n += 1
            continue
        if not include_comments and s.startswith("#"):
            continue
        n += 1
    return n

def should_exclude(rel_path: str, name: str, exclude_patterns: List[str]) -> bool:
    for pat in exclude_patterns:
        if fnmatch.fnmatch(name, pat) or fnmatch.fnmatch(rel_path, pat):
            return True
    return False

def walk_files(root: str, exclude_patterns: List[str]) -> Iterable[str]:
    root = os.path.abspath(root)
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        pruned = []
        for d in list(dirnames):
            rel = os.path.normpath(os.path.join(rel_dir, d))
            if should_exclude(rel, d, exclude_patterns):
                pruned.append(d)
        for d in pruned:
            dirnames.remove(d)
        for fname in filenames:
            rel_file = os.path.normpath(os.path.join(rel_dir, fname))
            if should_exclude(rel_file, fname, exclude_patterns):
                continue
            yield os.path.join(dirpath, fname)

def print_table(rows: List[Tuple[str, int, int]], unique_total_files: int) -> None:
    rows = rows + [("total", unique_total_files, sum(l for _, _, l in rows))]
    name_w = max(len(r[0]) for r in rows)
    files_w = max(len(str(r[1])) for r in rows)
    lines_w = max(len(str(r[2])) for r in rows)
    def fmt(name, f, l):
        return f"{name.ljust(name_w)}  {str(f).rjust(files_w)}  {str(l).rjust(lines_w)}"
    print()
    print("Category".ljust(name_w), " Files".rjust(files_w + 1), " Lines".rjust(lines_w + 1))
    print("-" * (name_w + files_w + lines_w + 4))
    for name, f, l in rows:
        print(fmt(name, f, l))
    print()

def process_ipynb(path: str, include_blank: bool, include_comments: bool) -> Tuple[int, int]:
    """
    Returns tuple of (python_code_lines, markdown_noncode_lines) from a notebook.
    """
    try:
        data = json.loads(read_text(path))
    except Exception:
        return (0, 0)
    code_lines = 0
    md_lines = 0
    for cell in data.get("cells", []):
        cell_type = cell.get("cell_type")
        src = cell.get("source", [])
        if isinstance(src, list):
            text = "".join(src)
        else:
            text = str(src or "")
        if cell_type == "code":
            code_lines += count_python_lines_from_text(text, include_blank, include_comments)
        elif cell_type == "markdown":
            md_lines += count_markdown_text_noncode_lines(text, include_blank)
    return code_lines, md_lines

def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        description="Count lines split by Python, Bash, PowerShell, SQL, YAML, and non-code Markdown lines, notebooks included."
    )
    p.add_argument("roots", nargs="*", default=["."], help="Root folder(s) to scan, default current folder.")
    p.add_argument("-e", "--exclude", nargs="*", default=[], help="Directory or file patterns to exclude, supports globs.")
    p.add_argument("--no-default-excludes", action="store_true", help="Turn off the default exclude list.")
    p.add_argument("--include-blank", action="store_true", help="Include blank lines in counts.")
    p.add_argument("--include-comments", action="store_true", help="Include comment only lines in code counts.")
    p.add_argument("-v", "--verbose", action="store_true", help="Show progress and file level details.")
    p.add_argument("--by-file", action="store_true", help="Print per file counts.")
    p.add_argument("--out", nargs=2, metavar=("format", "path"), help="Write a report file, format is 'json' or 'csv'.")
    args = p.parse_args(argv)

    exclude_patterns: List[str] = []
    if not args.no_default_excludes:
        exclude_patterns.extend(sorted(DEFAULT_EXCLUDES))
    for item in args.exclude:
        if "," in item:
            exclude_patterns.extend([x.strip() for x in item.split(",") if x.strip()])
        elif item:
            exclude_patterns.append(item)

    totals = Totals()
    per_file: List[Tuple[str, str, int]] = []  # (bucket, path, lines)

    for root in args.roots:
        root_abs = os.path.abspath(root)
        if args.verbose:
            print(f"Scanning {root_abs}")
        for path in walk_files(root_abs, exclude_patterns):
            bucket = classify_file(path)
            if not bucket:
                continue
            totals.unique_files.add(path)
            try:
                if bucket == "python":
                    n = count_python_lines(path, args.include_blank, args.include_comments)
                    totals.python.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "bash":
                    n = count_bash_lines(path, args.include_blank, args.include_comments)
                    totals.bash.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "powershell":
                    n = count_powershell_lines(path, args.include_blank, args.include_comments)
                    totals.powershell.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "sql":
                    n = count_sql_lines(path, args.include_blank, args.include_comments)
                    totals.sql.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "yaml":
                    n = count_yaml_lines(path, args.include_blank, args.include_comments)
                    totals.yaml.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "markdown_noncode":
                    n = count_markdown_noncode_lines(path, args.include_blank)
                    totals.markdown_noncode.add_file(n)
                    if args.by_file:
                        per_file.append((bucket, path, n))
                elif bucket == "ipynb":
                    py_n, md_n = process_ipynb(path, args.include_blank, args.include_comments)
                    if py_n:
                        totals.python.add_file(py_n)
                        if args.by_file:
                            per_file.append(("python", path + " [ipynb:code]", py_n))
                    if md_n:
                        totals.markdown_noncode.add_file(md_n)
                        if args.by_file:
                            per_file.append(("markdown_noncode", path + " [ipynb:markdown]", md_n))
                if args.verbose and (len(per_file) % 200 == 0):
                    print(f"  ... {len(per_file)} file entries processed")
            except Exception as ex:
                if args.verbose:
                    print(f"Failed to read {path}: {ex}", file=sys.stderr)

    rows = [
        ("python", totals.python.files, totals.python.lines),
        ("bash", totals.bash.files, totals.bash.lines),
        ("powershell", totals.powershell.files, totals.powershell.lines),
        ("sql", totals.sql.files, totals.sql.lines),
        ("yaml", totals.yaml.files, totals.yaml.lines),
        ("markdown_noncode", totals.markdown_noncode.files, totals.markdown_noncode.lines),
    ]
    print_table(rows, unique_total_files=len(totals.unique_files))

    if args.by_file:
        print("Per file breakdown")
        print("------------------")
        for bucket in ("python", "bash", "powershell", "sql", "yaml", "markdown_noncode"):
            files = [(b, p, n) for b, p, n in per_file if b == bucket]
            if not files:
                continue
            print(f"\n[{bucket}]")
            width = max(len(p) for _, p, _ in files)
            for _, pth, n in sorted(files, key=lambda x: x[1].lower()):
                print(f"{pth.ljust(width)}  {n}")

    if args.out:
        fmt, out_path = args.out
        fmt = fmt.lower().strip()
        if fmt not in {"json", "csv"}:
            print("Only json or csv supported for --out", file=sys.stderr)
            return 2
        out_path = os.path.abspath(out_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        if fmt == "json":
            payload = {
                "roots": [os.path.abspath(r) for r in args.roots],
                "exclude_patterns": exclude_patterns,
                "include_blank": args.include_blank,
                "include_comments": args.include_comments,
                "totals": totals.as_dict(),
                "files": [{"bucket": b, "path": p, "lines": n} for b, p, n in per_file],
            }
            with open(out_path, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
        else:
            import csv
            with open(out_path, "w", encoding="utf-8", newline="") as f:
                w = csv.writer(f)
                w.writerow(["bucket", "files", "lines"])
                for name, fcnt, lcnt in rows:
                    w.writerow([name, fcnt, lcnt])
                w.writerow(["total_unique_files", len(totals.unique_files), sum(r[2] for r in rows)])
                if args.by_file:
                    w.writerow([])
                    w.writerow(["bucket", "path", "lines"])
                    for b, pth, n in per_file:
                        w.writerow([b, pth, n])
        print(f"Report written to {out_path}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
