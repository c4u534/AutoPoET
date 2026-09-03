import json
import os
import ast
import csv

def analyze_ast(source_code, cell_idx):
    try:
        tree = ast.parse(source_code)
    except Exception:
        return [], []

    functions = []
    classes = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            classes.append({
                "name": node.name,
                "docstring": ast.get_docstring(node),
                "methods": [m.name for m in node.body if isinstance(m, ast.FunctionDef) or isinstance(m, ast.AsyncFunctionDef)],
                "cell_index": cell_idx
            })

        if isinstance(node, ast.FunctionDef) or isinstance(node, ast.AsyncFunctionDef):
            func_name = node.name

            # Simple check if function is just returning a constant, pass, or raise NotImplementedError
            is_hardcoded = False

            if len(node.body) == 1:
                stmt = node.body[0]
                if isinstance(stmt, ast.Return) and isinstance(stmt.value, ast.Constant):
                    is_hardcoded = True
                elif isinstance(stmt, ast.Pass):
                    is_hardcoded = True
                elif isinstance(stmt, ast.Raise):
                    is_hardcoded = True
            elif len(node.body) == 2:
                # Might have a docstring then return/pass/raise
                if isinstance(node.body[0], ast.Expr) and isinstance(node.body[1], ast.Return):
                    if isinstance(node.body[1].value, ast.Constant):
                        is_hardcoded = True
                elif isinstance(node.body[0], ast.Expr) and isinstance(node.body[1], ast.Pass):
                    is_hardcoded = True
                elif isinstance(node.body[0], ast.Expr) and isinstance(node.body[1], ast.Raise):
                    is_hardcoded = True

            functions.append({
                "name": func_name,
                "is_likely_hardcoded": is_hardcoded,
                "docstring": ast.get_docstring(node),
                "cell_index": cell_idx
            })
    return functions, classes

def analyze_notebooks():
    repo_data = {}

    for filename in os.listdir('.'):
        if filename.endswith('.ipynb'):
            file_data = {
                "functions": [],
                "classes": [],
                "markdown_summaries": [],
                "code_snippet_count": 0
            }

            try:
                with open(filename, 'r', encoding='utf-8') as f:
                    nb = json.load(f)
            except Exception as e:
                print(f"Error reading {filename}: {e}")
                continue

            cells = nb.get("cells", [])
            for cell_idx, cell in enumerate(cells):
                cell_type = cell.get("cell_type")
                source = "".join(cell.get("source", []))

                if cell_type == "markdown":
                    if len(source.strip()) > 0:
                        lines = [line.strip() for line in source.strip().split('\n') if line.strip() and not line.strip().startswith('<a href')]
                        if lines:
                            file_data["markdown_summaries"].extend(lines[:2]) # get top 2 lines for context
                elif cell_type == "code":
                    if len(source.strip()) > 0:
                        file_data["code_snippet_count"] += 1
                        funcs, cls = analyze_ast(source, cell_idx)
                        file_data["functions"].extend(funcs)
                        file_data["classes"].extend(cls)

            # Keep only a brief overview for the markdown summary
            file_data["markdown_summaries"] = list(dict.fromkeys(file_data["markdown_summaries"]))[:5]
            repo_data[filename] = file_data

    with open('repository_index.json', 'w', encoding='utf-8') as f:
        json.dump(repo_data, f, indent=4)

    return repo_data

def generate_csv(repo_data):
    with open('repository_index.csv', 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['File', 'Type', 'Name', 'Is Hardcoded/Stub', 'Cell Index', 'Docstring/Purpose'])

        for filename, data in repo_data.items():
            for cls in data['classes']:
                writer.writerow([filename, 'Class', cls['name'], False, cls['cell_index'], cls['docstring']])
            for func in data['functions']:
                writer.writerow([filename, 'Function', func['name'], func['is_likely_hardcoded'], func['cell_index'], func['docstring']])

def generate_readme(repo_data):
    lines = ["# AutoPoET Repository Documentation\n"]
    lines.append("This repository contains a comprehensive indexing of intelligence modalities, frameworks, and architecture components, primarily structured as Jupyter Notebooks.\n")
    lines.append("## Repository Overview\n")
    lines.append("We have performed a granular analysis of each file, identifying code blocks, classes, and functions. We also attempted to identify hardcoded or stubbed functions (functions that merely return a constant, pass, or raise NotImplementedError without real logic). The full details are available in `repository_index.json` and `repository_index.csv`.\n")

    for filename, data in repo_data.items():
        lines.append(f"### `{filename}`")
        if data["markdown_summaries"]:
            lines.append("**Context/Purpose:**")
            for summary in data["markdown_summaries"]:
                lines.append(f"- {summary}")
        lines.append(f"**Code Cells:** {data['code_snippet_count']}")

        if data["classes"]:
            lines.append("**Classes:**")
            for cls in data["classes"][:10]:
                doc = f" - {cls['docstring'][:50]}..." if cls['docstring'] else ""
                doc = doc.replace('\n', ' ')
                lines.append(f"- `{cls['name']}` (Cell {cls['cell_index']}){doc}")
            if len(data["classes"]) > 10:
                lines.append(f"- *...and {len(data['classes']) - 10} more.*")

        if data["functions"]:
            lines.append("**Key Functions Identified:**")
            for func in data["functions"][:15]:
                hardcoded_flag = " **(Likely Hardcoded/Stubbed)**" if func["is_likely_hardcoded"] else ""
                doc = f" - {func['docstring'][:50]}..." if func['docstring'] else ""
                doc = doc.replace('\n', ' ')
                lines.append(f"- `{func['name']}` (Cell {func['cell_index']}){hardcoded_flag}{doc}")
            if len(data["functions"]) > 15:
                lines.append(f"- *...and {len(data['functions']) - 15} more.*")
        lines.append("\n")

    with open('README.md', 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

if __name__ == "__main__":
    data = analyze_notebooks()
    generate_csv(data)
    generate_readme(data)
    print("Analysis complete. Generated repository_index.json, repository_index.csv and updated README.md.")
