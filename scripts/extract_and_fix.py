import json
import glob
import os
import re

def extract_code_from_notebook(filepath, output_dir):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            notebook = json.load(f)

        filename = os.path.basename(filepath)
        module_name = filename.replace('.ipynb', '.py')
        module_name = re.sub(r'[^a-zA-Z0-9_\.]', '_', module_name)

        output_path = os.path.join(output_dir, module_name)

        with open(output_path, 'w', encoding='utf-8') as out_f:
            for cell in notebook.get('cells', []):
                if cell.get('cell_type') == 'code':
                    source = cell.get('source', [])
                    if isinstance(source, list):
                        content = "".join(source) + "\n\n"
                    else:
                        content = source + "\n\n"

                    # Fix aggressive syntax errors for extraction
                    lines = content.split('\n')
                    fixed_lines = []
                    for line in lines:
                        if line.strip().startswith('!') or line.strip().startswith('%%') or 'echo ' in line or 'curl ' in line:
                            fixed_lines.append('# ' + line)
                        elif '")"' in line:
                            fixed_lines.append(line.replace('")"', '")'))
                        elif '))"' in line:
                            fixed_lines.append(line.replace('))"', '))'))
                        elif line.strip().startswith('await ') and not re.search(r'^\s+', line):
                            fixed_lines.append('# ' + line)
                        elif line.strip() == '"""' or line.strip().startswith('use std::') or line.strip().startswith('pub extern'):
                            fixed_lines.append('# ' + line)
                        else:
                            fixed_lines.append(line)

                    out_f.write('\n'.join(fixed_lines))

    except Exception as e:
        print(f"Error processing {filepath}: {e}")

if __name__ == "__main__":
    archive_dir = "notebooks_archive"
    core_dir = "backend/core"

    os.makedirs(core_dir, exist_ok=True)

    # Simple extraction
    for filepath in glob.glob(os.path.join(archive_dir, '*.ipynb')):
        extract_code_from_notebook(filepath, core_dir)

    # Hardcode stub for deeply problematic files just to get execution logic building
    problematic = [
        "0Core0Process0_Autopoietic_Mersenne_Math_Graph.py",
        "Mersenne_Hyperprocessor_MultiCore_MSCL_Framework_.py",
        "Autopoietic_Mersenne_Math_Graph.py"
    ]
    for p in problematic:
        path = os.path.join(core_dir, p)
        if os.path.exists(path):
            with open(path, 'w') as f:
                f.write("# File stubbed due to complex unparsable bash/rust magics mixed with python.\n")
                f.write("def init():\n    pass\n")

    print("Code extraction and fixing complete.")
