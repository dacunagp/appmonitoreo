import 'package:utm/utm.dart';

void main() {
  var utm = UTM.fromLatLon(lat: -33.456, lon: -70.654);
  print('zone: ${utm.zone}');
  print('easting: ${utm.easting}');
  print('northing: ${utm.northing}');
  print('latBand: ${utm.latBand}');
}
