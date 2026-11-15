import json

with open(r"C:\Users\mahmooud\.gemini\antigravity\brain\59aa8762-b7ea-407c-a1fd-22750bf7f91b\.system_generated\logs\transcript_full.jsonl", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        data = json.loads(line)
        si = data.get("step_index")
        if data.get("type") == "USER_INPUT" and si in range(4000, 5000):
            print(f"STEP {si}:")
            c = str(data.get("content", ""))[:200]
            print(c.encode('ascii', 'backslashreplace').decode('ascii'))
