import os

'''
Just get the repo structure output for checking, 
mainly for private_ files as these not shown in external/public mkdocs structure. 
'''


# Extend exclusion lists
EXCLUDE_DIRS = {
    '.git', '__pycache__', '.vscode', '.idea', '.github', '.pytest_cache', '.env', 'venv', 'd2i_dev_depreciated_BAK', 'admin', 'd2i_dev', 'docs'
    'site', 'assets', 'javascripts', 'stylesheets', 'images', 'fonts', 'workers', 'lunr'
}
EXCLUDE_FILES = {
    '.DS_Store', 'Thumbs.db'
}

def build_tree(start_path='.', prefix=''):
    lines = []
    try:
        entries = sorted(os.listdir(start_path))
    except PermissionError:
        return lines

    files = [
        f for f in entries
        if os.path.isfile(os.path.join(start_path, f)) and f not in EXCLUDE_FILES
    ]
    dirs = [
        d for d in entries
        if os.path.isdir(os.path.join(start_path, d)) and d not in EXCLUDE_DIRS
    ]

    for index, directory in enumerate(dirs):
        connector = '├── ' if index < len(dirs) - 1 or files else '└── '
        lines.append(prefix + connector + directory + '/')
        extension = '│   ' if index < len(dirs) - 1 or files else '    '
        lines.extend(build_tree(os.path.join(start_path, directory), prefix + extension))

    for i, file in enumerate(files):
        connector = '├── ' if i < len(files) - 1 else '└── '
        lines.append(prefix + connector + file)

    return lines

if __name__ == '__main__':
    repo_name = os.path.basename(os.path.abspath('.'))
    tree_lines = [f"{repo_name}/"] + build_tree('.')

    # plain text version
    txt_path = './admin/repo_structure_overview.txt'
    with open(txt_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(tree_lines))
    print(f"project structure in {txt_path}")

    # markdown version
    md_path = './admin/repo_structure_overview.md'
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write('# Repo Structure\n\n')
        f.write('```text\n')
        f.write('\n'.join(tree_lines))
        f.write('\n```\n')
    print(f"project structure in {md_path}")







# import os

# def write_repo_structure(output_file="d2i_dev/dev_repo_structure.txt", include_dir=None, exclude_dirs=None):
#     base_dir = os.getcwd()  # get curr dir
#     output_lines = []

#     def walk_dir(directory, prefix=""):
#         items = sorted(os.listdir(directory))
#         for i, item in enumerate(items):
#             item_path = os.path.join(directory, item)
            
#             # skip excluded dirs
#             if exclude_dirs and any(item_path.endswith(exclude) for exclude in exclude_dirs):
#                 continue

#             is_last = (i == len(items) - 1)
#             branch = "└── " if is_last else "├── "
#             output_lines.append(f"{prefix}{branch}{item}")
            
#             if os.path.isdir(item_path):
#                 extension = "    " if is_last else "│   "
#                 walk_dir(item_path, prefix=prefix + extension)

#     # including specific dir, start there
#     if include_dir:
#         base_dir = os.path.join(base_dir, include_dir)
#         if not os.path.exists(base_dir):
#             print(f"Error: Directory '{include_dir}' does not exist.")
#             return

#     output_lines.append(f"{os.path.basename(base_dir)}/")  # root folder
#     walk_dir(base_dir)

#     with open(output_file, "w") as f:
#         f.write("\n".join(output_lines))

#     print(f"Repository structure written to {output_file}")



# # spec include dir or exclude folders
# write_repo_structure(
#     output_file="dev_repo_structure.txt",
#     include_dir="/workspaces/dfe_csc_api_data_flows",  # from this point
#     exclude_dirs=[".git", ".env", "venv", "__pycache__", "d2i_dev_depreciated_BAK"]  # ignore
# )