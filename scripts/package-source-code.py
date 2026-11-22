import os
import zipfile
import tarfile
from pathlib import Path

ROOT = Path("D:/Tamreedy")
DEPLOY_DIR = ROOT / "deploy"
DEPLOY_DIR.mkdir(exist_ok=True)

EXCLUDE_DIRS = {
    "node_modules",
    "build",
    ".dart_tool",
    ".gradle",
    "dist",
    ".git",
    "deploy",
    ".idea",
    ".vscode",
    "__pycache__",
    ".gemini",
    ".antigravity-server",
    ".system_generated",
    "gradle-cache"
}

# Real secrets / private files that should NEVER be exported
EXCLUDE_EXACT_FILES = {
    ".env",
    "fcm.json",
    "fcm-service-account.json",
    "google-services.json"
}

EXCLUDE_EXTS = {
    ".apk",
    ".aab",
    ".tar.gz",
    ".zip",
    ".log",
    ".tmp"
}

CODE_EXTS = {
    ".dart", ".ts", ".tsx", ".js", ".mjs", ".cjs",
    ".json", ".yaml", ".yml", ".sql", ".html", ".css",
    ".md", ".xml", ".gradle", ".properties", ".sh", ".ps1", ".bat"
}

SPECIAL_CODE_FILENAMES = {
    "Dockerfile", "Dockerfile.api", "Dockerfile.worker", "Dockerfile.admin",
    ".dockerignore", ".env.example", ".env.prod.example", "pnpm-workspace.yaml",
    "pnpm-lock.yaml", "README.md", "nginx-admin.conf"
}

def is_code_file(p: Path) -> bool:
    if p.name in SPECIAL_CODE_FILENAMES:
        return True
    return p.suffix.lower() in CODE_EXTS

def should_include(rel_path: Path, code_only: bool = False) -> bool:
    # Check directory parts
    for part in rel_path.parts:
        if part in EXCLUDE_DIRS:
            return False
        if part.startswith(".") and part not in {".github", ".env.example", ".env.prod.example", ".dockerignore"}:
            if part in {".git", ".idea", ".vscode", ".dart_tool", ".gradle"}:
                return False

    name = rel_path.name
    if name in EXCLUDE_EXACT_FILES:
        return False
    
    suffix = rel_path.suffix.lower()
    if suffix in EXCLUDE_EXTS:
        return False
        
    if code_only and not is_code_file(rel_path):
        return False
    
    return True

def get_files(category: str, code_only: bool = False):
    """
    category: 'all', 'mobile', 'backend'
    """
    selected_files = []
    
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # Prune excluded directories in-place
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        
        rel_dir = Path(dirpath).relative_to(ROOT)
        
        for f in filenames:
            file_rel = rel_dir / f
            if not should_include(file_rel, code_only=code_only):
                continue
            
            str_path = file_rel.as_posix()
            
            if category == 'mobile':
                # mobile apps + shared package
                if not (str_path.startswith("apps/patient_app/") or 
                        str_path.startswith("apps/nurse_app/") or 
                        str_path.startswith("packages/flutter_core/") or
                        str_path in {"README.md", "pnpm-workspace.yaml", "package.json"}):
                    continue
            elif category == 'backend':
                # backend API + worker + admin web + infra + scripts + docs + root configs
                if (str_path.startswith("apps/patient_app/") or 
                    str_path.startswith("apps/nurse_app/") or 
                    str_path.startswith("packages/flutter_core/")):
                    continue
            
            selected_files.append((ROOT / file_rel, file_rel))
            
    return selected_files

def create_zip(zip_path: Path, files):
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for full_path, rel_path in files:
            zf.write(full_path, arcname=rel_path.as_posix())
    mb = round(zip_path.stat().st_size / (1024 * 1024), 2)
    kb = round(zip_path.stat().st_size / 1024, 1)
    size_str = f"{mb} MB" if mb >= 1.0 else f"{kb} KB"
    print(f"Done: {zip_path.name:<38} ({len(files):>3} files, {size_str})")
    return size_str

def create_tar_gz(tar_path: Path, files):
    if tar_path.exists():
        tar_path.unlink()
    with tarfile.open(tar_path, 'w:gz') as tf:
        for full_path, rel_path in files:
            tf.add(full_path, arcname=rel_path.as_posix())
    mb = round(tar_path.stat().st_size / (1024 * 1024), 2)
    kb = round(tar_path.stat().st_size / 1024, 1)
    size_str = f"{mb} MB" if mb >= 1.0 else f"{kb} KB"
    print(f"Done: {tar_path.name:<38} ({len(files):>3} files, {size_str})")
    return size_str

if __name__ == "__main__":
    print("=== Packaging Tamreedy Source Code ===")
    
    # 1. PURE CODE ONLY (Best for AI Models: fast, no binary bloat)
    pure_code_files = get_files('all', code_only=True)
    create_zip(DEPLOY_DIR / "tamreedy-code-pure.zip", pure_code_files)
    
    # 2. PURE CODE MOBILE
    mobile_code_files = get_files('mobile', code_only=True)
    create_zip(DEPLOY_DIR / "tamreedy-mobile-code.zip", mobile_code_files)
    
    # 3. PURE CODE BACKEND & ADMIN
    backend_code_files = get_files('backend', code_only=True)
    create_zip(DEPLOY_DIR / "tamreedy-backend-code.zip", backend_code_files)
    
    # 4. FULL REPO (with icons, fonts, design assets)
    full_files = get_files('all', code_only=False)
    create_zip(DEPLOY_DIR / "tamreedy-all-source-with-assets.zip", full_files)
    create_tar_gz(DEPLOY_DIR / "tamreedy-all-source.tar.gz", full_files)
    
    print("=== All packages created successfully in deploy/ ===")
