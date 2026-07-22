"""ctp-core must stay a pure library (Architecture P1 / A5): no FastAPI
import, ever. Enforced as a test, not a code-review convention.

Checks actual import statements (via ast), not substring matches — a
docstring explaining that ctp_core has no FastAPI dependency shouldn't trip
its own guard."""

import ast
from pathlib import Path

CTP_CORE_DIR = Path(__file__).parent.parent / "ctp_core"


def _imports_fastapi(path: Path) -> bool:
    tree = ast.parse(path.read_text(), filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name.split(".")[0] == "fastapi" for alias in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if node.module and node.module.split(".")[0] == "fastapi":
                return True
    return False


def test_ctp_core_never_imports_fastapi():
    offenders = [path.name for path in CTP_CORE_DIR.glob("*.py") if _imports_fastapi(path)]
    assert not offenders, f"ctp_core must not import fastapi, found imports in: {offenders}"
