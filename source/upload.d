module upload;

import std.file;
import std.conv;
import std.array;
import std.algorithm;
import std.regex;
import serverino;
import session;
import sqlite;

@endpoint @route!("/upload")
void upload(Request request, Output output) {
	Session session = Session(request, output, "test.db");
	int user_id = session.load();
  if (request.method == Request.Method.Get) {
		// TODO: Replace this with proper templating
		import std.logger;
		info(user_id);
		if(user_id >= 0) {
			output.serveFile("public/upload.html");
		} else {
			output.status = 302;
			output.addHeader("Location", "/");
			output ~= "No access!" ~ "\n" ~ "You are being redirected.";
		}
	} else if (request.method == Request.Method.Post) {
		if (user_id == -1) {
			output.status = 302;
			output.addHeader("Location", "/");
			output ~= "No access!" ~ "\n" ~ "You are being redirected.";
			return;
		}
		
		import std.logger;
		import core.stdc.time;
		time_t unixTime = core.stdc.time.time(null);

		const Request.FormData fd = request.form.read("image");
    const float latitude = to!float(request.form.read("lat").data);
    const float longitude = to!float(request.form.read("long").data);
		if(fd.isFile() && (fd.path.endsWith(".png") || fd.path.endsWith(".jpg"))) {
			info("File ", fd.filename, " uploaded at ", fd.path);
			
			// make sure file doesnt override (even if 2 files are uploaded the same second)
			string temp_path = fd.path;
			string target_path;
      string suffix = matchFirst(fd.filename, ctRegex!`(\.\w+)$`)[1];
			int i = 0;
			do {
				target_path = "photos/" ~ to!string(unixTime) ~ "_" ~ to!string(i++) ~ suffix;
			} while (exists(target_path));
			
			temp_path.copy(target_path);
			info("copied file to: ", target_path);

      scope Database db = new Database("test.db", OpenFlags.READWRITE);
      try {
        db.exec(db.prepare_bind!(string, float, float, int)("
          INSERT INTO photos (path, latitude, longitude, user_id)
          VALUES (?, ?, ?, ?) 
        ", target_path, latitude, longitude, user_id));
      } catch (Database.DBException e) {
        error("An exception occured during insertion of photo in database:
            ", e.msg);
      }
			output ~= "image received\n";
		}
	}
  output.status = 405;
}
