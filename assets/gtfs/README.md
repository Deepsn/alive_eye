Two files from SPTrans' GTFS package belong here. Download it from
https://www.sptrans.com.br/desenvolvedores/ (same login as the API token) and
unzip it somewhere:

1. Copy `stops.txt` here as `assets/gtfs/stops.txt` — every bus stop in the
   city, instead of the ~360 corridor stops the Olho Vivo API lists.
2. Generate `assets/gtfs/routes.txt` from the unzipped package:

   ```sh
   dart run tool/build_routes.dart <unzipped-gtfs-dir>
   ```

   This reads `routes.txt`, `trips.txt`, `stop_times.txt` and (if present)
   `shapes.txt`, and writes the ordered stop sequence plus the street geometry
   for each line and direction. Do not copy the GTFS `routes.txt` here directly
   — the generated file has a different format and the same name.

Then rebuild the app. Without step 2 the line view can only draw the corridor
stops the API reports, which is a fraction of each line's real route.
