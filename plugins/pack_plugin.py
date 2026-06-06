# encoding: utf-8
"""Tessera 插件打包工具

将一个包含 plugin.json 的目录打包成项目可识别的 .plugin 文件

用法：
    python plugins/pack_plugin.py validate <folder> [--strict] [--skip-lua-check]
    python plugins/pack_plugin.py pack <folder> [-o OUTPUT] [--include-hidden] [--skip-lua-check]

ZIP 内部布局: 
    plugin.json                <- 必填，扁平于根
    main.lua                   <- 入口脚本（entryPoint，可改名）
    icon.png, README.md, ...   <- 任意可选资源（运行时由 Lua 自行 require/读取）

plugin.json schema: 
    id          必填，反向域名风格，如 "com.example.my_plugin"
    name        可选，默认 ""
    version     可选，默认 "0.0.0"
    author      可选，默认 ""
    description 可选，默认 ""
    entryPoint  可选，默认 "main.lua"
    homepage    可选，默认 null
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import List, Tuple

# -----------------------------------------------------------------------------
# 常量
# -----------------------------------------------------------------------------

# 打包时默认排除的目录 / 文件 / 后缀
EXCLUDE_DIRS = {".git", "__pycache__", ".idea", ".vscode", "node_modules"}
EXCLUDE_FILES = {".DS_Store", "Thumbs.db"}
EXCLUDE_SUFFIX = {".pyc", ".pyo"}

# 宽松的 semver 匹配（不做强约束，仅给出 warning）
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+([-+].*)?$")

EXIT_OK = 0
EXIT_VALIDATION = 1
EXIT_IO = 2

# -----------------------------------------------------------------------------
# 清单解析
# -----------------------------------------------------------------------------

@dataclass
class Manifest:
    id: str
    name: str
    version: str
    author: str
    description: str
    entryPoint: str
    homepage: str | None

    @classmethod
    def load(cls, folder: Path) -> "Manifest":
        """读取 <folder>/plugin.json，缺失或格式错误抛 ValueError。"""
        path = folder / "plugin.json"
        if not path.is_file():
            raise ValueError(f"找不到 plugin.json: {path}")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise ValueError(f"plugin.json 不是合法 JSON ({path}): {e}") from e
        if not isinstance(data, dict):
            raise ValueError(f"plugin.json 顶层必须是对象 (got {type(data).__name__})")

        return cls(
            id=str(data.get("id", "") or ""),
            name=str(data.get("name", "") or ""),
            version=str(data.get("version", "") or "0.0.0"),
            author=str(data.get("author", "") or ""),
            description=str(data.get("description", "") or ""),
            entryPoint=str(data.get("entryPoint", "") or "main.lua"),
            homepage=(str(data["homepage"]) if data.get("homepage") else None),
        )

    def issues(self, folder: Path) -> Tuple[List[str], List[str]]:
        """返回 (errors, warnings)。"""
        errors: List[str] = []
        warnings: List[str] = []

        if not self.id:
            errors.append('plugin.json 中缺少必填字段 "id"')

        if self.id and "." not in self.id:
            warnings.append(
                f'id "{self.id}" 不是反向域名风格（建议如 "com.example.my_plugin"）'
            )

        if not SEMVER_RE.match(self.version):
            warnings.append(
                f'version "{self.version}" 不是标准 semver（建议如 "1.0.0"）'
            )

        if not self.entryPoint:
            errors.append('plugin.json 中 entryPoint 为空')
        else:
            entry_abs = folder / self.entryPoint
            if not entry_abs.is_file():
                errors.append(
                    f'entryPoint 指向的文件不存在: {self.entryPoint}'
                )
            elif entry_abs.stat().st_size == 0:
                warnings.append(
                    f'entryPoint 指向的文件为空: {self.entryPoint}'
                )

        if not self.name:
            warnings.append('plugin.json 中 "name" 为空')

        return errors, warnings


# -----------------------------------------------------------------------------
# 文件收集
# -----------------------------------------------------------------------------

def collect_files(folder: Path, include_hidden: bool) -> List[Path]:
    """收集要打包的文件，相对 folder 的扁平路径。"""
    folder = folder.resolve()
    result: List[Path] = []
    for p in sorted(folder.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(folder)
        parts = rel.parts
        if not include_hidden and any(part.startswith(".") for part in parts):
            continue
        if any(part in EXCLUDE_DIRS for part in parts[:-1]):
            continue
        if p.name in EXCLUDE_FILES:
            continue
        if p.suffix in EXCLUDE_SUFFIX:
            continue
        result.append(p)
    return result


# -----------------------------------------------------------------------------
# 路径解析
# -----------------------------------------------------------------------------

def _sanitize_id(id_: str) -> str:
    return id_.replace(".", "_").replace("-", "_")


def default_output(folder: Path, m: Manifest) -> Path:
    """默认输出：<folder>/../<id>-<version>.plugin（与插件目录同级）。"""
    safe_id = _sanitize_id(m.id) or "plugin"
    version = m.version or "0.0.0"
    return folder.parent / f"{safe_id}-{version}.plugin"


def resolve_output(folder: Path, m: Manifest, output: Path | None) -> Path:
    """解析 -o 参数：
    - 未指定 → 与插件目录同级的 <id>-<version>.plugin
    - 是已存在的目录 → 该目录下的 <id>-<version>.plugin
    - 否则 → 当作文件路径使用
    """
    if output is None:
        return default_output(folder, m)
    if output.is_dir():
        safe_id = _sanitize_id(m.id) or "plugin"
        version = m.version or "0.0.0"
        return output / f"{safe_id}-{version}.plugin"
    return output

# -----------------------------------------------------------------------------
# 语法分析（Lua 静态编译检测）
# -----------------------------------------------------------------------------

@dataclass(frozen=True)
class LuaCheckResult:
    """单个 .lua 文件的静态编译检查结果。"""
    file: Path
    ok: bool
    line: int | None = None     # 1-based 行号，从 LuaSyntaxError 消息中正则提取
    message: str = ""           # 已剥掉 [string "<python>"]: 前缀的纯描述


def check_lua_syntax(file: Path) -> LuaCheckResult:
    """对单个 .lua 文件做编译期静态语法检查（只编译，不执行）。

    懒加载 lupa.lua53；若 lupa 未安装会抛 ImportError，由调用方负责处理。
    """
    import lupa.lua53 as _lupa  # 懒加载；Python 会缓存到 sys.modules

    if not file.is_file():
        return LuaCheckResult(file=file, ok=False, message=f"file not found: {file}")

    try:
        src = file.read_text(encoding="utf-8")
    except UnicodeDecodeError as e:
        return LuaCheckResult(file=file, ok=False, message=f"not valid UTF-8: {e}")

    try:
        _lupa.LuaRuntime(unpack_returned_tuples=True).compile(src)
        return LuaCheckResult(file=file, ok=True)
    except _lupa.LuaSyntaxError as e:
        msg = str(e)
        # lupa 错误消息格式: [string "<python>"]:N: <description>
        m = re.search(r"\]:(\d+):", msg)
        line = int(m.group(1)) if m else None
        clean = re.sub(r'^\[string "<python>"\]:\d+:\s*', "", msg)
        return LuaCheckResult(file=file, ok=False, line=line, message=clean)


def run_lua_checks(folder: Path, skip: bool) -> tuple[list[LuaCheckResult], bool]:
    """对 folder 内所有 .lua 文件执行静态语法检查。

    返回 (results, lupa_missing):
        - skip=True 时直接返回 ([], False)，调用方完全跳过 Lua 检查。
        - 未安装 lupa 时返回 ([], True)，由调用方打印可操作的错误信息并退出。
        - 否则复用 collect_files 的排除规则收集 .lua 文件，逐个 check_lua_syntax。
    """
    if skip:
        print("WARNING: Skipping Lua syntax checks. Use at your own risk!")
        return [], False
    try:
        import lupa.lua53  # noqa: F401  仅探测可用性
    except ImportError:
        return [], True

    print(f"Running Lua syntax checks in {folder}...")
    lua_files = [
        p for p in collect_files(folder, include_hidden=False) if p.suffix == ".lua"
    ]
    return [check_lua_syntax(p) for p in lua_files], False

# -----------------------------------------------------------------------------
# 子命令：validate
# -----------------------------------------------------------------------------

def cmd_validate(args: argparse.Namespace) -> int:
    folder = args.folder.resolve()
    if not folder.is_dir():
        print(f"✗ Directory not exist: {folder}", file=sys.stderr)
        return EXIT_IO

    print(f"Validating plugin directory: {folder}")

    try:
        m = Manifest.load(folder)
    except ValueError as e:
        print(f"✗ {e}")
        return EXIT_VALIDATION

    print(f"✓ manifest:  {folder / 'plugin.json'}")
    print(f"  id:          {m.id or '(空)'}")
    print(f"  name:        {m.name or '(空)'}")
    print(f"  version:     {m.version}")
    print(f"  author:      {m.author or '(空)'}")
    print(f"  description: {m.description or '(空)'}")
    print(f"  entryPoint:  {m.entryPoint}")

    errors, warnings = m.issues(folder)

    # Lua 静态检查 — 与 --strict 无关，语法错误一律视为 error
    lua_results, lupa_missing = run_lua_checks(folder, skip=args.skip_lua_check)
    if lupa_missing:
        print(
            "✗ FAILED: Lua syntax checks skipped due to lupa not being installed.\n"
            "  Please run `pip install lupa` or use --skip-lua-check to proceed.",
            file=sys.stderr,
        )
        return EXIT_IO
    lua_errors = [r for r in lua_results if not r.ok]
    for r in lua_results:
        rel = r.file.relative_to(folder).as_posix()
        if r.ok:
            print(f"✓ lua syntax: {rel}")
        else:
            loc = f":{r.line}" if r.line is not None else ""
            print(f"✗ FAILED: lua syntax error in {rel}{loc}: {r.message}")

    for w in warnings:
        marker = "✗" if args.strict else "!"
        print(f"{marker} {w}")

    for e in errors:
        print(f"✗ FAILED: {e}")

    if errors or lua_errors:
        print(
            f"\nValidation failed: {len(errors)} error(s), "
            f"{len(warnings)} warning(s), {len(lua_errors)} lua error(s)."
        )
        return EXIT_VALIDATION
    if args.strict and warnings:
        print(f"\nValidation failed (strict): {len(warnings)} warning(s).")
        return EXIT_VALIDATION

    print(
        f"\nValidation passed ({len(warnings)} warning(s), "
        f"{len(lua_errors)} lua error(s))."
    )
    return EXIT_OK


# -----------------------------------------------------------------------------
# 子命令：pack
# -----------------------------------------------------------------------------

def _human_size(n: int) -> str:
    units = ["B", "KB", "MB", "GB"]
    f = float(n)
    for u in units:
        if f < 1024 or u == units[-1]:
            return f"{f:.1f} {u}" if u != "B" else f"{int(f)} {u}"
        f /= 1024
    return f"{n} B"


def _self_check(zip_path: Path) -> None:
    """读回打包好的 ZIP，校验 plugin.json 可解析且字段齐全。"""
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        if "plugin.json" not in names:
            raise RuntimeError("自检失败: 打包后的 ZIP 中找不到 plugin.json")
        raw = zf.read("plugin.json")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"自检失败: plugin.json 无法被 JSON 解析: {e}") from e
    if not isinstance(data, dict) or not str(data.get("id", "") or ""):
        raise RuntimeError("自检失败: plugin.json 缺少 id 字段")


def cmd_pack(args: argparse.Namespace) -> int:
    folder = args.folder.resolve()
    if not folder.is_dir():
        print(f"✗ FAILED: Directory not exist: {folder}", file=sys.stderr)
        return EXIT_IO

    # 1) 复用 validate
    try:
        m = Manifest.load(folder)
    except ValueError as e:
        print(f"✗ FAILED: {e}")
        return EXIT_VALIDATION

    errors, warnings = m.issues(folder)
    if errors:
        for e in errors:
            print(f"✗ FAILED: {e}")
        return EXIT_VALIDATION

    # Lua 静态检查 — 放在任何文件 I/O 副作用之前，fail fast 不留半成品
    lua_results, lupa_missing = run_lua_checks(folder, skip=args.skip_lua_check)
    if lupa_missing:
        print(
            "✗ FAILED: Lua syntax checks skipped due to lupa not being installed.\n"
            "  Please run `pip install lupa` or use --skip-lua-check to proceed.",
            file=sys.stderr,
        )
        return EXIT_IO
    lua_errors = [r for r in lua_results if not r.ok]
    for r in lua_results:
        rel = r.file.relative_to(folder).as_posix()
        if r.ok:
            print(f"  ✓ lua syntax: {rel}")
        else:
            loc = f":{r.line}" if r.line is not None else ""
            print(f"  ✗ FAILED: lua syntax error in {rel}{loc}: {r.message}")
    if lua_errors:
        return EXIT_VALIDATION

    for w in warnings:
        marker = "✗" if args.strict else "!"
        print(f"{marker} {w}")
    if args.strict and warnings:
        return EXIT_VALIDATION

    # 2) 解析输出路径
    output = resolve_output(folder, m, args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if output.exists() and not args.force:
        print(f"✗ FAILED: Output file exists: {output} (use --force to overwrite)")
        return EXIT_IO

    # 3) 收集文件
    files = collect_files(folder, include_hidden=args.include_hidden)
    if not files:
        print("✗ FAILED: No files found to pack.")
        return EXIT_VALIDATION

    print(f"Packaging {folder} -> {output}")
    total_raw = 0

    # 4) 写入 ZIP（扁平，posix 风格路径）
    try:
        with zipfile.ZipFile(
            output, "w", zipfile.ZIP_DEFLATED, compresslevel=6
        ) as zf:
            for src in files:
                rel = src.relative_to(folder)
                arcname = str(PurePosixPath(rel.as_posix()))
                zinfo = zipfile.ZipInfo(arcname)
                zinfo.compress_type = zipfile.ZIP_DEFLATED
                data = src.read_bytes()
                zf.writestr(zinfo, data)
                total_raw += len(data)
                print(f"  + {arcname} ({_human_size(len(data))})")
    except Exception:
        # 写失败时清理半成品
        if output.exists():
            output.unlink()
        raise

    # 5) 统计压缩后大小 + 6) 自检
    total_zip = output.stat().st_size
    try:
        _self_check(output)
    except Exception as e:
        if output.exists():
            output.unlink()
        print(f"✗ FAILED: {e}")
        return EXIT_VALIDATION

    print(
        f"\nPacked {len(files)} files "
        f"(raw {_human_size(total_raw)}, zip {_human_size(total_zip)})"
    )
    print(f"✓ Successfully packed plugin -> {output}")
    return EXIT_OK


# -----------------------------------------------------------------------------
# 入口
# -----------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pack_plugin.py",
        description="Tessera 插件校验与打包工具",
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="<command>")

    p_val = sub.add_parser("validate", help="校验 plugin.json 与入口文件")
    p_val.add_argument("folder", type=Path, help="包含 plugin.json 的插件目录")
    p_val.add_argument(
        "--strict", action="store_true", help="把 warning 视为 error"
    )
    p_val.add_argument(
        "--skip-lua-check", action="store_true",
        help="跳过 .lua 文件的静态语法检查（未安装 lupa 时使用）",
    )

    p_pack = sub.add_parser("pack", help="打包成 .plugin（ZIP）")
    p_pack.add_argument("folder", type=Path, help="包含 plugin.json 的插件目录")
    p_pack.add_argument(
        "-o", "--output", type=Path, default=None,
        help="输出路径（文件 / 目录 / 不传=与插件目录同级）",
    )
    p_pack.add_argument(
        "--include-hidden", action="store_true",
        help="包含以 . 开头的隐藏文件（默认排除）",
    )
    p_pack.add_argument(
        "--force", action="store_true", help="覆盖已存在的输出文件"
    )
    p_pack.add_argument(
        "--strict", action="store_true", help="把 warning 视为 error"
    )
    p_pack.add_argument(
        "--skip-lua-check", action="store_true",
        help="跳过 .lua 文件的静态语法检查（未安装 lupa 时使用）",
    )

    return parser


def main(argv: List[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "validate":
        return cmd_validate(args)
    if args.command == "pack":
        return cmd_pack(args)
    parser.print_help()
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
