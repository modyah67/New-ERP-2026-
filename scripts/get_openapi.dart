import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('Fetching OpenAPI spec from Supabase...');
  final url = Uri.parse('https://pjkhdnoeyyvraclomepx.supabase.co/rest/v1/');
  final headers = {
    'apikey': 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
    'Authorization': 'Bearer sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
  };

  try {
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      final file = File('openapi.json');
      await file.writeAsString(response.body);
      print('OpenAPI spec saved to openapi.json (${response.body.length} characters)');
    } else {
      print('Failed to fetch OpenAPI spec. Status code: ${response.statusCode}');
      print('Response: ${response.body}');
    }
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
