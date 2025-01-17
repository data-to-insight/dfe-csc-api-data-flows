import os

def write_repo_structure(output_file="d2i_dev/dev_repo_structure.txt", include_dir=None, exclude_dirs=None):
    base_dir = os.getcwd()  # get curr dir
    output_lines = []

    def walk_dir(directory, prefix=""):
        items = sorted(os.listdir(directory))
        for i, item in enumerate(items):
            item_path = os.path.join(directory, item)
            
            # skip excluded dirs
            if exclude_dirs and any(item_path.endswith(exclude) for exclude in exclude_dirs):
                continue

            is_last = (i == len(items) - 1)
            branch = "└── " if is_last else "├── "
            output_lines.append(f"{prefix}{branch}{item}")
            
            if os.path.isdir(item_path):
                extension = "    " if is_last else "│   "
                walk_dir(item_path, prefix=prefix + extension)

    # including specific dir, start there
    if include_dir:
        base_dir = os.path.join(base_dir, include_dir)
        if not os.path.exists(base_dir):
            print(f"Error: Directory '{include_dir}' does not exist.")
            return

    output_lines.append(f"{os.path.basename(base_dir)}/")  # root folder
    walk_dir(base_dir)

    with open(output_file, "w") as f:
        f.write("\n".join(output_lines))

    print(f"Repository structure written to {output_file}")



# spec include dir or exclude folders
write_repo_structure(
    output_file="dev_repo_structure.txt",
    include_dir="/workspaces/csc_api_data_collection",  # from this point
    exclude_dirs=[".git", ".env", "venv", "__pycache__", "d2i_dev_depreciated_BAK"]  # ignore
)