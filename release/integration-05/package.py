from pathlib import Path, PurePosixPath
from hashlib import sha256
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
import struct

work = Path(__file__).resolve().parent
root = work.parents[1]
name = "RawFront-Radiant-0.5-win64"
parser = argparse.ArgumentParser()
parser.add_argument("base_zip", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--base-sha256", required=True)
parser.add_argument("--cod2-import-dir", required=True, type=Path)
args = parser.parse_args()
if sha256(args.base_zip.read_bytes()).hexdigest() != args.base_sha256.lower():
    parser.error("Input archive SHA-256 does not match the build manifest")
files = {
    "README-PL.txt": "README-PL.txt",
    "Start_RawFront_Radiant.cmd": "Start_RawFront_Radiant.cmd",
    "Start_RawFront_Radiant.ps1": "Start_RawFront_Radiant.ps1",
    "Play_Map.ps1": "Play_Map.ps1",
    "Support/default_build_menu.xml": "default_build_menu.xml",
    "Support/radiant_extensions.ent": "radiant_extensions.ent",
    "Support/Prepare_Gameplay_Textures.ps1": "Prepare_Gameplay_Textures.ps1",
}

for filename in ("Import_CoD2_Map.cmd", "Import_CoD2_Map.ps1",
                 "import_cod2_map.py", "cod2-compatibility.json"):
    path = (args.cod2_import_dir / filename).resolve(strict=True)
    if not path.is_file():
        parser.error(f"Missing CoD2 import file: {path.name}")
    files[filename] = path

args.output.parent.mkdir(exist_ok=True, parents=True)
with ZipFile(args.base_zip) as source, ZipFile(args.output, "x", ZIP_DEFLATED) as output:
    assert source.testzip() is None
    for item in source.infolist():
        path = PurePosixPath(item.filename)
        assert not path.is_absolute() and ".." not in path.parts
        if item.is_dir() or path.parts[0] in ("gamepacks", "settings"):
            continue
        if path.suffix.lower() in (".map", ".ttf", ".log", ".pref", ".pid", ".bak"):
            continue
        output.writestr(f"{name}/{path}", source.read(item))
    for directory in ("gamepacks/games", "settings"):
        output.writestr(f"{name}/{directory}/", b"")
    for destination, local in files.items():
        output.write(work / local, f"{name}/{destination}")

with ZipFile(args.output) as output:
    assert output.testzip() is None
    names = output.namelist()
    assert len(names) == len(set(n.lower() for n in names))
    for path in ("radiant.exe", "Qt5Core.dll", "Qt5Gui.dll", "Qt5Widgets.dll", "Qt5Svg.dll",
                 "share/qt5/plugins/platforms/qwindows.dll"):
        data = output.read(f"{name}/{path}")
        offset = struct.unpack_from("<I", data, 0x3c)[0]
        assert data[offset:offset+6] == b"PE\0\0\x64\x86", path
    for item in output.infolist():
        lower = item.filename.lower()
        assert not any(token in lower for token in ("/.git/", "/modding/", "/rawfront-workspace/", "/play-appdata/", ".map"))
        if lower.endswith((".txt", ".xml", ".ent", ".cmd", ".ps1", ".cfg", ".conf", ".ini")):
            body = output.read(item).lower()
            assert b"c:\\users\\" not in body and b"c:/users/" not in body and b"codex-runtimes" not in body
digest = sha256(args.output.read_bytes()).hexdigest()
args.output.with_suffix(".zip.sha256").write_text(f"{digest}  {args.output.name}\n", encoding="ascii")
print(digest, len(names), args.output.stat().st_size)
