import os
import re

directory = r"C:\Users\Mazen\Desktop\New folder\ERP\lib\features"

pattern = re.compile(r"SizedBox\s*\(\s*width\s*:\s*_col([a-zA-Z0-9_]+)\s*,")
replacement = r"Expanded(flex: _col\1.toInt(),"

files_modified = 0

for root, dirs, files in os.walk(directory):
    for file in files:
        if file.endswith("statement_page.dart"):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = pattern.sub(replacement, content)
            
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Modified: {file}")
                files_modified += 1

print(f"Total files modified: {files_modified}")
