import urllib.request
import urllib.error
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

SUPABASE_URL = "https://rakdzuvlauphupkywoik.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJha2R6dXZsYXVwaHVwa3l3b2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjYyNTksImV4cCI6MjEwNDgwMjI1OX0.gK5YRX3oCy8VHLeFcfcw9I1jfZY3gE75tflyyP_owZk"

headers = {
    "apikey": ANON_KEY,
    "Authorization": f"Bearer {ANON_KEY}",
    "Content-Type": "application/json"
}

def get(endpoint):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8')
    except Exception as e:
        return 0, str(e)

st, tt = get("treasury_transactions?select=*&limit=1")
print("treasury_transactions cols:", list(tt[0].keys()) if isinstance(tt, list) and tt else tt)

st, jl = get("journal_entry_lines?select=*&limit=1")
print("journal_entry_lines cols:", list(jl[0].keys()) if isinstance(jl, list) and jl else jl)

st, je = get("journal_entries?select=*&limit=1")
print("journal_entries cols:", list(je[0].keys()) if isinstance(je, list) and je else je)
