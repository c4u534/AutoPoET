import os
import glob
import traceback

def test_syntax_of_extracted_files():
    core_dir = "backend/core"
    python_files = glob.glob(os.path.join(core_dir, "*.py"))

    if not python_files:
        print("No Python files found to test.")
        exit(1)

    failures = 0

    for filepath in python_files:
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                source = f.read()
            compile(source, filepath, 'exec')
        except SyntaxError as e:
            print(f"Syntax error in {filepath}:")
            traceback.print_exc()
            failures += 1
        except Exception as e:
            print(f"Other error reading {filepath}: {e}")
            failures += 1

    if failures == 0:
        print("All extracted files have valid syntax!")
        exit(0)
    else:
        print(f"Failed with {failures} syntax errors.")
        exit(1)

if __name__ == "__main__":
    test_syntax_of_extracted_files()
