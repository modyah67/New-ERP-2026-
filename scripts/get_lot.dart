import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final url = Uri.parse('https://pjkhdnoeyyvraclomepx.supabase.co/rest/v1/lot_receipts?select=id,product_name,purchase_mode,carton_count,gross_weight_kg,net_weight_kg,price_per_carton,fruit_cost_per_kg,total_fruit_cost');
  final headers = {
    'apikey': 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
    'Authorization': 'Bearer sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  };
  final res = await http.get(url, headers: headers);
  print(res.body);
}
