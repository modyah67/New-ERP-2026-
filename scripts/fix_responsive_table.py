import re

files = [
    r"lib/features/clearing_agents/clearing_agent_statement_page.dart",
    r"lib/features/exports/export_customer_statement_page.dart",
    r"lib/features/shipping_companies/shipping_company_statement_page.dart",
    r"lib/features/statements/supplier_statement_page.dart",
    r"lib/features/suppliers/supplier_account_statement_page.dart",
    r"lib/features/shareholders/shareholder_statement_page.dart"
]

for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # Replace SizedBox(width: _colX, child: ...) with Expanded(flex: _colX.toInt(), child: ...)
        content = re.sub(
            r'SizedBox\(\s*width:\s*(_col[a-zA-Z]+),\s*child:',
            r'Expanded(flex: \1.toInt(), child:',
            content
        )

        # Replace Expanded(child: Text('البيان', ...)) with Expanded(flex: _colDesc.toInt(), child: Text('البيان', ...))
        content = re.sub(
            r"Expanded\(\s*child:\s*Text\('البيان'",
            r"Expanded(flex: _colDesc.toInt(), child: Text('البيان'",
            content
        )

        # Replace Expanded(child: Text(row.description ...)) with Expanded(flex: _colDesc.toInt(), child: Text(row.description ...))
        content = re.sub(
            r'Expanded\(\s*child:\s*Text\(\s*row\.description',
            r'Expanded(flex: _colDesc.toInt(), child: Text(\n              row.description',
            content
        )
        
        # Replace Expanded(child: Text(row.notes ...)) for description if notes is used
        content = re.sub(
            r'Expanded\(\s*child:\s*Text\(\s*row\.notes',
            r'Expanded(flex: _colDesc.toInt(), child: Text(\n              row.notes',
            content
        )

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
            
        print(f"Updated {filepath}")
    except FileNotFoundError:
        print(f"File not found: {filepath}")
        
