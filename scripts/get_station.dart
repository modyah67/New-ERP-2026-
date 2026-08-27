import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final url = Uri.parse('https://pjkhdnoeyyvraclomepx.supabase.co/rest/v1/station_products');
  final headers = {
    'apikey': 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
    'Authorization': 'Bearer sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  };
  final res = await http.get(url, headers: headers);
  print(res.body);
}
