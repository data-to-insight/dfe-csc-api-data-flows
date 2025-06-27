import os
import re

folder = "api_pipeline"

# Target modules to correct (top-level)
target_modules = {"config", "auth", "db", "utils", "payload"}

pattern = re.compile(rf"^from ({'|'.join(target_modules)}) import", re.MULTILINE)

for root, _, files in os.walk(folder):
    for file in files:
        if file.endswith(".py"):
            path = os.path.join(root, file)
            with open(path, encoding="utf-8") as f:
                content = f.read()

            updated_content = pattern.sub(r"from .\1 import", content)

            if updated_content != content:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(updated_content)
                print(f"✔️ Fixed imports in {path}")
