import urllib.request
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJha2R6dXZsYXVwaHVwa3l3b2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjYyNTksImV4cCI6MjEwNDgwMjI1OX0.gK5YRX3oCy8VHLeFcfcw9I1jfZY3gE75tflyyP_owZk',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJha2R6dXZsYXVwaHVwa3l3b2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjYyNTksImV4cCI6MjEwNDgwMjI1OX0.gK5YRX3oCy8VHLeFcfcw9I1jfZY3gE75tflyyP_owZk'
}

req = urllib.request.Request('https://rakdzuvlauphupkywoik.supabase.co/rest/v1/account_ledger_entries?journal_entry_id=eq.16&select=*', headers=headers)
with urllib.request.urlopen(req) as resp:
    lines = json.loads(resp.read().decode())
    print('Journal Entry 16 lines count:', len(lines))
    for l in lines:
        print(f"ID: {l.get('id')}, Acct: {l.get('account_id')}, Dr: {l.get('debit')}, Cr: {l.get('credit')}, Desc: {l.get('description')}")

