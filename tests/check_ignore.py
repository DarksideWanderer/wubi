"""Check publication exclusions without initializing or changing the real repository."""
from pathlib import Path
import shutil
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
IGNORED = [
    "dist/WubiCoach.exe", "dist/macOS/WubiCoach.app/Contents/MacOS/WubiCoach",
    "artifacts/WubiCoach.zip", "WubiCoach-portable.zip", "WubiCoach-macOS.zip",
    "macos/.build/debug/WubiCoach", "macos/.swiftpm/configuration/workspace-state.json",
    "DerivedData/cache", "project.xcodeproj/xcuserdata/user.xcuserdatad/state.xcuserstate",
    ".DS_Store", "macos/._Info.plist", "Thumbs.db", ".env", ".env.local",
    "tests/ime-preview.png", "tests/keyboard-result.txt", "test-error.log",
    "src/obj/cache", "src/bin/WubiCoach.exe", "tests/__pycache__/cache.pyc",
]
TRACKED = [
    ".gitignore", ".gitattributes", ".github/workflows/build.yml", "README.md", "LICENSE",
    "THIRD-PARTY.md", "build.ps1", "src/MainWindow.cs", "data/roots.ttf",
    "data/decomposition.tsv", "data/wubi86.dict.yaml", "data/corpus.txt",
    "macos/Package.swift", "macos/Package.resolved", "macos/build.sh",
    "macos/Resources/Info.plist", "macos/Sources/WubiCore/LearningEngine.swift",
    "macos/Tests/WubiCoreTests/CoreTests.swift", "tests/fixtures/predictions.json",
    "tests/check_ignore.py", ".env.example",
]


def main():
    # The temporary Git directory is isolated under the OS temporary directory.
    # Verify its resolved location before TemporaryDirectory recursively cleans it.
    with tempfile.TemporaryDirectory(prefix="wubi-ignore-") as directory:
        root = Path(directory).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve()
        assert root.name.startswith("wubi-ignore-")
        shutil.copyfile(PROJECT / ".gitignore", root / ".gitignore")
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)
        result = subprocess.run(
            ["git", "-C", str(root), "-c", "core.excludesFile=", "check-ignore", "--no-index", "--stdin", "-z"],
            input=("\0".join(IGNORED + TRACKED) + "\0").encode("utf-8"), capture_output=True,
        )
        assert result.returncode in (0, 1), result.stderr
        actual = set(filter(None, result.stdout.decode("utf-8").split("\0")))
        assert actual == set(IGNORED), f"Unexpected ignore results: {actual.symmetric_difference(IGNORED)}"
        print(f"PASS: {len(IGNORED)} generated/private paths excluded; {len(TRACKED)} source/data paths retained")


if __name__ == "__main__":
    main()
