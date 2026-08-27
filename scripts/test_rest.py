import urllib.request
import json

url = "https://pjkhdnoeyyvraclomepx.supabase.co/rest/v1/purchase_invoices?select=id&limit=1"
headers = {
    "apikey": "sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L",
    "Authorization": "Bearer sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L"
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        html = response.read()
        print(html.decode('utf-8'))
except Exception as e:
    print("Error:", e)
