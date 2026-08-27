import urllib.request
import json

url = "https://pjkhdnoeyyvraclomepx.supabase.co/rest/v1/rpc/exec_sql"
headers = {
    "apikey": "sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L",
    "Authorization": "Bearer sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L",
    "Content-Type": "application/json"
}
data = json.dumps({"query": "SELECT 1 as val"}).encode('utf-8')

req = urllib.request.Request(url, data=data, headers=headers, method="POST")
try:
    with urllib.request.urlopen(req) as response:
        html = response.read()
        print(html.decode('utf-8'))
except Exception as e:
    print("Error:", e)
