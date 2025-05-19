module upload;

import std.file;
import std.conv;
import std.array;
import std.algorithm;
import std.regex;
import std.process : environment;
import serverino;

import mustache;

import session;
import sqlite;
import logger;

alias MustacheEngine!(string) Mustache;

@endpoint @route!("/upload")
void upload(Request request, Output output) {
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;
		
	int user_id = session_load(request, output);
	if(user_id <= 0) {
		output.status = 302;
		output.addHeader("Location", "/login");
		output ~= "No access!" ~ "\n" ~ "You are being redirected.";
		return;
	}
	
  mustache_context.useSection("logged_in");
	
	if (request.method == Request.Method.Post) {
		import std.logger;
		import core.stdc.time;
		time_t unixTime = core.stdc.time.time(null);

		const Request.FormData fd = request.form.read("image");
    const float latitude = to!float(request.form.read("lat").data);
    const float longitude = to!float(request.form.read("long").data);
		if(fd.isFile() && (fd.path.endsWith(".png") || fd.path.endsWith(".jpg"))) {
			flogger.info("File ", fd.filename, " uploaded at ", fd.path);
			
			// make sure file doesnt override (even if 2 files are uploaded the same second)
			string temp_path = fd.path;
			string target_path;
      string suffix = matchFirst(fd.filename, ctRegex!`(\.\w+)$`)[1];
			int i = 0;
			do {
				target_path = "photos/" ~ to!string(unixTime) ~ "_" ~ to!string(i++) ~ suffix;
			} while (exists(target_path));
			
			temp_path.copy(target_path);
			flogger.info("copied file to: ", target_path);

      scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
      try {
        db.exec(db.prepare_bind!(string, float, float, string, int)("
          INSERT INTO photos (path, latitude, longitude, location, user_id)
          VALUES (?, ?, ?, ?, ?)", target_path, latitude, longitude, "garching", user_id));
        mustache_context.addSubContext("info_messages")["info_message"] = "Photo submitted for review.";
      } catch (Database.DBException e) {
        error("An exception occured during insertion of photo in database:
            ", e.msg);
        mustache_context.addSubContext("error_messages")["info_message"] = "Database error.";
      }
		}
	}
	output ~= mustache.render("upload", mustache_context);
  output.status = 200;
}
