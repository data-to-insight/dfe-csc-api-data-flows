import subprocess
from pathlib import Path

# Markdown files in desired order
files = [
    "docs/theme/cover.md",  
    "docs/index.md",
    "docs/system_requirements.md",
    "docs/deploy_ssd.md",
    "docs/api_config.md"
]


# Output file
output = Path("site/pdf/csc_ssd_api_documentation.docx")
output.parent.mkdir(parents=True, exist_ok=True)

# Pandoc command with Word-specific options
cmd = [
    "pandoc",
    "--toc",                     # Table of contents
    "--toc-depth=3",            # Up to h3
    "-s",                       # Standalone document
    "-o", str(output),
    *files
]

# Run it
result = subprocess.run(cmd, capture_output=True, text=True)

# # Output info for debugging
# print({
#     "return_code": result.returncode,
#     "stdout": result.stdout,
#     "stderr": result.stderr,
#     "output_file": str(output)
# })
