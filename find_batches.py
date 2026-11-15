import json

with open(r"C:\Users\mahmooud\.gemini\antigravity\brain\59aa8762-b7ea-407c-a1fd-22750bf7f91b\.system_generated\logs\transcript_full.jsonl", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        data = json.loads(line)
        si = data.get("step_index")
        c = json.dumps(data)
        if "apply_transport_batches" in c or "TransportBatchModel" in c:
            print(f"STEP {si}: {data.get('type')}")

