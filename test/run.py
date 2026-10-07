"""Headless check of Pole Tidy on vanilla, and with power-propagation (pass "pp")."""
import json, shutil, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT))
from factorio_paths import PATHS  # noqa: E402
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "pt-mods"
if MODS.exists():
    shutil.rmtree(MODS)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "pole-tidy", ignore=shutil.ignore_patterns("test"))
shutil.copytree(HERE / "pt-test", MODS / "pt-test")
names = ["base", "elevated-rails", "quality", "space-age", "pole-tidy", "pt-test"]
if "pp" in sys.argv:
    pp = next(PATHS["user_mods"].glob("power-propagation_*.zip"))
    shutil.copy(pp, MODS / pp.name)
    names.append("power-propagation")
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
out = RUN / "script-output" / "pt-test.txt"
out.unlink(missing_ok=True)
save = RUN / "pt-test.zip"
save.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
for args in (["--create", str(save)], ["--benchmark", str(save), "--benchmark-ticks", "140", "--disable-audio"]):
    p = subprocess.run(common + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode or "non-recoverable" in p.stdout or "Error" in p.stdout:
        print(p.stdout[-3000:]); sys.exit(1)
print(out.read_text() if out.exists() else "no result")
