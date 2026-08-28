import pathlib
import re


root = pathlib.Path(__file__).resolve().parents[1] / "com.marehori.nowplaying.sdPlugin"
html = (root / "PropertyInspector" / "index.html").read_text(encoding="utf-8")
javascript = (root / "PropertyInspector" / "index.js").read_text(encoding="utf-8")
ids = re.findall(r'\bid="([^"]+)"', html)
assert len(ids) == len(set(ids)), "duplicate HTML ids"
binding = javascript[javascript.index("function bindControls"):javascript.index("document.addEventListener")]
references = set(re.findall(r'"([A-Za-z][A-Za-z0-9]+)"', binding))
missing = sorted(value for value in references if value not in ids and value not in {"input", "change", "click", "openUrl"})
assert not missing, f"missing ids: {missing}"
print(f"PASS: {len(ids)} unique UI ids and all bound controls exist")
