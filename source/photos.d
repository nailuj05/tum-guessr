module photos;

import std.process : environment;
import std.algorithm;
import std.conv;
import std.stdio;
import std.file;

import serverino;
import mustache;

import sqlite;
import session;
import logger;
import pageselect;
import header;

alias MustacheEngine!(string) Mustache;

@endpoint @route!(r => r.path.startsWith("/photos")) @priority(999) 
void photos_access_authorization(Request request, Output output) {
	int user_id = session_load(request, output);
	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
	auto query_result = db.query!(string, int, int)(db.prepare_bind!int("
		SELECT username, is_admin, is_trusted
		FROM users
		WHERE user_id=?
	", user_id));
	if (query_result.length < 1) {
		flogger.warning("unknown user attempted admin access without valid session.");
		output.status = 403;
		output ~= "Permission denied. This incident will be reported.";
		return;
	}
	string username = query_result[0][0];
	int is_admin = query_result[0][1];
	int is_trusted = query_result[0][2];
	if (!is_admin && !is_trusted) {
		flogger.warning("User ", user_id, " aka '", username, "' attempted admin/trusted access on path ",
										request.path, " without privileges.");
		output.status = 403;
		output ~= "Permission denied. This incident will be reported.";
		return;
	}
}

@endpoint @route!"/photos/view" @route!(r => r.get.has("photo_id"))
void photos_view(Request r, Output output) {
	scope(failure) {
		output.status = 404;
		output ~= "failed to load image";
	}
	
	int photo_id = to!int(r.get.read("photo_id", "-1"));

	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);

	if (!photo_exists(photo_id, db)) {
		output.status = 404;
		output ~= "failed to load image";
		return;
	}

  Stmt stmt = db.prepare_bind!(int)("SELECT path, latitude, longitude, is_accepted FROM photos WHERE photo_id = ?", photo_id);
	auto rows = db.query!(string, double, double, int)(stmt);
	auto row = rows[0];
  
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, r, output);
	
	mustache_context["path"] = row[0];
	mustache_context["lat"] = row[1];
	mustache_context["long"] = row[2];
	mustache_context["photo_id"] = photo_id;
  mustache_context["accept"] = row[3] == 1 ? "Unaccept" : "Accept";

	output ~= mustache.render("photos_view", mustache_context);
}

// TODO: Photo List Endpoint (display all currently unaccepted images
@endpoint @route!"/photos/list"
void photos_list(Request r, Output output) {
  scope(failure) output.status = 404;

	int limit = to!int(r.get.read("limit", "30"));
	int page = to!int(r.get.read("page", "0"));
  int offset = page * limit;

	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);

  int num_photos = db.query_imm!int("SELECT count(*) FROM photos WHERE is_accepted = false")[0][0];
  int max_pages = num_photos / limit;

  Stmt stmt = db.prepare_bind!(int, int)("SELECT photo_id, path FROM photos WHERE is_accepted = false LIMIT ? OFFSET ?", limit, offset);
  auto rows = db.query!(int, string)(stmt);
  
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, r, output);
	
	page_context(mustache_context, "/photos/list", page, max_pages, limit);

	foreach (ref row; rows) {
		auto mustache_subcontext = mustache_context.addSubContext("photos");
    
		mustache_subcontext["photo_id"] = row[0];
		mustache_subcontext["path"] = row[1];
	}
	
	output ~= mustache.render("photos_list", mustache_context);
}

// TODO: Accept Endpoint
@endpoint @route!"/photos/accept"
void photos_accept(Request r, Output output) {
	if (request.method != POST) {
		output.status = 405;
		return;
	}
	scope(failure) output.status = 404;

	int user_id = session_load(r, output);
	int photo_id = to!int(r.post.read("photo_id", "-1"));

  flogger.info("photo: ", photo_id, " accepted by ", user_id);

	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);

	if (!photo_exists(photo_id, db)) {
		output.status = 404;
		return;
	}

	scope(failure) output ~= "acception failed";
	scope(failure) flogger.error("Photo: ", photo_id, " failed to be accepted");
	Stmt stmt = db.prepare_bind!(int)("UPDATE photos SET is_accepted = NOT is_accepted WHERE photo_id = ?",
																		photo_id);
	db.exec(stmt);

	output.status = 302;
	output.addHeader("Location", "/photos/list");
	output ~= "updated successfully";
}

@endpoint @route!"/photos/delete"
void photos_delete(Request r, Output output) {
	if (request.method != POST) {
		output.status = 405;
		return;
	}
	scope(failure) output.status = 404;
	
	int user_id = session_load(r, output);
	int photo_id = to!int(r.post.read("photo_id", "-1"));

  flogger.info("photo: ", photo_id, " deleted by ", user_id);
  
	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);

	if (!photo_exists(photo_id, db)) {
		output.status = 404;
		return;
	}

	scope(failure) output ~= "deletion failed";

	// Get Path and remove the image
	{
    scope(failure) flogger.error("file deletion of photo: ", photo_id, " failed");
    Stmt stmt = db.prepare_bind!(int)("SELECT path FROM photos WHERE photo_id = ?", photo_id);
    string file = db.query!(string)(stmt)[0][0];
    remove(file);
  }
  
  // Remove Image from DB
  scope(failure) flogger.error("database deletion of photo: ", photo_id, " failed");
	Stmt stmt = db.prepare_bind!(int)("DELETE FROM photos WHERE photo_id = ?", photo_id);
	db.exec(stmt);

	output.status = 302;
	output.addHeader("Location", "/photos/list");
	output ~= "deleted successfully";
}

bool photo_exists(int photo_id, ref Database db) {
	Stmt stmt = db.prepare_bind!(int)("SELECT COUNT(*) FROM photos WHERE photo_id = ?", photo_id);
	auto query_result = db.query!(int)(stmt);
	
	return query_result[0][0] > 0;
}
