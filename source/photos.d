module photos;

import std.process : environment;
import std.algorithm;
import std.conv;
import std.stdio;

import serverino;
import mustache;

import sqlite;
import session;
import logger;

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
		flogger.warning("Unknown user attempted admin access without valid session.");
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
	
	// Display both photo and coordinate location with option to accept or delete

	output ~= "PhotoID: " ~ to!string(photo_id);
}

// TODO: Photo List Endpoint (display all currently unaccepted images
@endpoint @route!"/photos/list"
void photos_list(Request r, Output output) {

}

// TODO: Accept Endpoint
@endpoint @route!"/photos/accept" @route!(r => r.post.has("photo_id"))
void photos_accept(Request r, Output output) {
	scope(failure) output.status = 404
	
	int photo_id = to!int(r.post.read("photo_id", "-1"));

	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);

	if (!photo_exists(photo_id, db)) {
		output.status = 404;
		return;
	}

	scope(failure) output ~= "acception failed";
	scope(failure) flogger.error("Photo: ", photo_id, " failed to be accepted");
	Stmt stmt = db.prepare_bind!(int)("UPDATE photos SET is_accepted = 1 WHERE photo_id = ?",
																		photo_id);
	db.exec(stmt);

	output ~= "accepted successfully"
}

@endpoint @route!"/photos/delete" @route!(r => r.post.has("photo_id"))
void photos_delete(Request r, Output output) {
	scope(failure) output.status = 404
	
	int photo_id = to!int(r.post.read("photo_id", "-1"));

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

	output ~= "deleted successfully"
}

bool photo_exists(int photo_id, ref Database db) {
	Stmt stmt = db.prepare_bind!(int)("SELECT COUNT(*) FROM photos WHERE photo_id = ?", photo_id);
	auto query_result = db.query!(int)(stmt);
	
	return query_result[0][0] > 0;
}
