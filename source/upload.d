module upload;

import std.file;
import std.conv;
import std.array;
import std.algorithm;
import std.regex;
import std.datetime;
import std.path;
import std.process : executeShell, environment;
import serverino;

import mustache;

import session;
import sqlite;
import header;
import logger;

alias MustacheEngine!(string) Mustache;

@endpoint @route!("/upload/guideline")
void guideline(Request request, Output output) {  
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;
		
  set_header_context(mustache_context, request, output);

  output ~= mustache.render("guideline", mustache_context);
  output.status = 200;
}

bool isValidFilename(string name) {
    // Reject if name contains directory components or dangerous characters
    if (name.canFind("/") || name.canFind("\\") || name.canFind("..")) return false;

    // Allow only alphanumeric, dash, underscore, and dot
    return cast(bool)matchFirst(name, ctRegex!`^[a-zA-Z0-9_.-]+$`);
}

@endpoint @route!("/upload")
void upload(Request request, Output output) {
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;
		
	int user_id = set_header_context(mustache_context, request, output);
	if(user_id <= 0) {
		output.status = 302;
		output.addHeader("Location", "/login");
		output ~= "No access!" ~ "\n" ~ "You are being redirected.";
		return;
	}
		
	if (request.method == Request.Method.Post) {
		import std.logger;
    long timestamp = Clock.currTime.toUnixTime;

		const Request.FormData fd = request.form.read("image");
    const float latitude = to!float(request.form.read("lat").data);
    const float longitude = to!float(request.form.read("long").data);
		if(fd.isFile() && (fd.path.endsWith(".png") || fd.path.endsWith(".jpg")) && request.form.read("agree").data == "on") {
			flogger.info("File ", fd.filename, " uploaded at ", fd.path);

      // make sure only these files can be uploaded
      string[] ftypes = [".png", ".jpg", ".jpeg"];
      if(!ftypes.canFind(extension(fd.filename))) {
        flogger.error("image type ", fd.filename, " not supported");
        mustache_context.addSubContext("error_messages")["info_message"] = "Image file not supported.";
      }
      else {
        // make sure file doesnt override (even if 2 files are uploaded the same second)
        string temp_path = fd.path;
        string target_path;
        int i = 0;
        do {
          target_path = "photos/" ~ to!string(timestamp) ~ "_" ~ to!string(i++) ~ ".jpg";
        } while (exists(target_path));

        if(!isValidFilename(fd.filename)) {
          flogger.error("Suspicious file uploaded, aborting: ", temp_path);
        } else {
          string cmd = "magick " ~ temp_path ~ " -resize 1200x800^ -gravity center -extent 1200x800 -quality 85 " ~ target_path;

          auto result = executeShell(cmd);
          if (result.status != 0) {
            flogger.error("Image Conversion failed: ", result.output);
          }
          
          flogger.info("Image uploaded: ", target_path);
        
          scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
          try {
            db.exec(db.prepare_bind!(string, float, float, string, int, long)("
          INSERT INTO photos (path, latitude, longitude, location, uploader_id, upload_time)
          VALUES (?, ?, ?, ?, ?, ?)", target_path, latitude, longitude, "garching", user_id, timestamp));
            mustache_context.addSubContext("info_messages")["info_message"] = "Photo submitted for review.";
          } catch (Database.DBException e) {
            flogger.error("An exception occured during insertion of photo in database:
            ", e.msg);
            mustache_context.addSubContext("error_messages")["info_message"] = "Database error.";
          }
        }
      }
		}
	}
	output ~= mustache.render("upload", mustache_context);
  output.status = 200;
}

