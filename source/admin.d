module admin;

import std.algorithm;
import std.conv;
import std.file;
import std.logger;
import std.array;
import std.datetime;
import std.process : environment;
import std.exception : enforce;

import serverino;
import mustache;

import sqlite;
import session;
import logger;
import pageselect;
import header;

alias MustacheEngine!(string) Mustache;

@endpoint @route!(r => r.path.startsWith("/admin")) @priority(999) 
void admin_access_authorization(Request request, Output output) {
	int user_id = session_load(request, output);
	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
	auto query_result = db.query!(string, int)(db.prepare_bind!int("
		SELECT username, is_admin
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
	if (!is_admin) {
		flogger.warning("User " ~ to!string(user_id) ~ " aka '" ~ username ~ "' attempted
				admin access on path " ~ request.path ~ " without privileges.");
		output.status = 403;
		output ~= "Permission denied. This incident will be reported.";
		return;
	}
}

@endpoint @route!"/admin" @route!"/admin/"
void admin(Request request, Output output) {
	output.status = 302;
	output.addHeader("Location", "/admin/users");
	output ~= "You are being redirected.";
}

@endpoint @route!"/admin/users"
void admin_users(Request request, Output output) {
	if (request.method != Request.Method.Get) {
		output.status = 405;
	}

  const string default_option = "user_id";
  
	string order    = request.get.read("order", "asc") == "asc" ? "asc" : "desc";
  string order_by = request.get.read("order_by", default_option);
	int limit       = to!int(request.get.read("limit", "30"));
	int page        = to!int(request.get.read("page", "0"));
  int offset      = page * limit;

	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  int num_users = db.query_imm!int("SELECT count(*) FROM users")[0][0];
  int max_pages = num_users / limit;
  
  string[] order_options = ["user_id", "username", "sign_up_time", "is_admin", "is_trusted", "is_deactivated"];
  string order_option = order_options.canFind(order_by) ? order_by : default_option;
  
  Stmt stmt = db.prepare_bind!(int, int)("
		SELECT user_id, username, sign_up_time, is_admin, is_trusted, is_deactivated
		FROM users
		ORDER BY " ~ order_option ~ " " ~ order ~ "
		LIMIT ? OFFSET ?", limit, offset);
	auto query_result = db.query!(int, string, int, int, int, int)(stmt);

	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, request, output);

	page_context(mustache_context, "/admin/users", page, max_pages, limit, order, order_option, order_options);

	import std.uri;
	foreach (ref row; query_result) {
		auto mustache_subcontext = mustache_context.addSubContext("users");
		mustache_subcontext["user_id"] = row[0];
		mustache_subcontext["username"] = row[1];
		mustache_subcontext["username_uri_encoded"] = row[1].encodeComponent;
		mustache_subcontext["sign_up_time"] = SysTime.fromUnixTime(row[2]).toString;
		mustache_subcontext["admin_value"] = 1 - row[3];
		mustache_subcontext["admin_checked"] = row[3] == 1 ? "checked" : "";
		mustache_subcontext["trusted_value"] = 1 - row[4];
		mustache_subcontext["trusted_checked"] = row[4] == 1 ? "checked" : "";
		mustache_subcontext["deactivated_value"] = 1 - row[5];
		mustache_subcontext["deactivated_checked"] = row[5] == 1 ? "checked" : "";
	}

	if (request.get.has("error")) {
		mustache_context.addSubContext("error_messages")["error_message"] = request.get.read("error");
	} else if (request.get.has("info")) {
		mustache_context.addSubContext("info_messages")["info_message"] = request.get.read("info");
	}
	
	output ~= mustache.render("admin_users", mustache_context);
}

@endpoint @route!"/admin/photos"
void admin_photos(Request request, Output output) {
	if (request.method != Request.Method.Get) {
		output.status = 405;
	}

  const string default_option = "photo_id";
  
	string order    = request.get.read("order", "asc") == "asc" ? "asc" : "desc";
	string order_by = request.get.read("order_by", default_option);
	int limit       = to!int(request.get.read("limit", "30"));
	int page        = to!int(request.get.read("page", "0"));
  int offset      = page * limit;
	
	
	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  int num_photos = db.query_imm!int("SELECT count(*) FROM photos")[0][0];
  int max_pages = num_photos / limit;
  
  string[] order_options = ["photo_id", "location", "username", "is_accepted"];
  string order_option = order_options.canFind(order_by) ? order_by : default_option;

  Stmt stmt = db.prepare_bind!(int, int)("
		SELECT p.photo_id, p.path, u.username, p.is_accepted, p.location
		FROM photos_with_acceptance p JOIN users u ON p.uploader_id == u.user_id
		ORDER BY " ~ order_option ~ " " ~ order ~ "
		LIMIT ? OFFSET ?", limit, offset);
  auto query_result = db.query!(int, string, string, int, string)(stmt);
	
	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, request, output);
	
	page_context(mustache_context, "/admin/photos", page, max_pages, limit, order, order_option, order_options);

	import std.uri;
	foreach (ref row; query_result) {
		auto mustache_subcontext = mustache_context.addSubContext("photos");
    bool is_accepted = row[3] == 1;
    
		mustache_subcontext["photo_id"] = row[0];
		mustache_subcontext["path"] = row[1];
		mustache_subcontext["username"] = row[2];
		mustache_subcontext["username_uri_encoded"] = row[2].encodeComponent;
		mustache_subcontext["is_accepted"] = is_accepted ? "checked" : "";
    mustache_subcontext["location"] = row[4];
	}
	
	output ~= mustache.render("admin_photos", mustache_context);
}

@endpoint @route!"/admin/reports"
void admin_reports(Request request, Output output) {
	if (request.method != Request.Method.Get) {
		output.status = 405;
	}

  Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, request, output);

  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  auto rows = db.query_imm!(int, string, string, int, string)("SELECT r.report_id, u.username, r.report_text, r.photo_id, p.path
    FROM reports r
    JOIN photos p ON r.photo_id = p.photo_id
    JOIN users u ON r.user_id = u.user_id
  ");

  foreach(row; rows) {
		auto mustache_subcontext = mustache_context.addSubContext("reports");
    mustache_subcontext["report_id"] = row[0];
    mustache_subcontext["username"]   = row[1];
    mustache_subcontext["message"]   = row[2];
    mustache_subcontext["photo_id"]  = row[3];
    mustache_subcontext["path"]      = row[4];
  }

  output ~= mustache.render("admin_reports", mustache_context);
}

@endpoint @route!(r => r.path == "/admin/report-delete" && r.post.has("report_id"))
void admin_report_delete(Request request, Output output) {
	if (request.method != Request.Method.Post) {
		output.status = 405;
	}
  
  int report_id = to!int(request.post.read("report_id"));
  scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
  db.exec(db.prepare_bind!(int)("DELETE FROM reports WHERE report_id = ?", report_id));

	output.status = 302;
	output.addHeader("Location", "/admin/reports");
	output ~= "You are being redirected.";
}

@endpoint @route!"/admin/log"
void admin_log(Request request, Output output) {
	if (request.method != Request.Method.Get) {
		output.status = 405;
	}

	Mustache mustache;
	mustache.path("public");
	scope auto mustache_context = new Mustache.Context;

  set_header_context(mustache_context, request, output);

	mustache_context["log"] = readText("logs/log.txt");
	
	output ~= mustache.render("admin_log", mustache_context);
}

@endpoint @route!(r => r.path == "/admin/set" && r.get.has("id") && r.get.has("role") && r.get.has("value"))
void set_role(Request request, Output output) {
	if (request.method != Request.Method.Get) {
		output.status = 405;
	}

  bool has_limit = request.get.has("limit");
	string limit = request.get.read("limit");
	string page = request.get.read("page", "0");

	scope(success) output.addHeader("Location", "/admin/users?page=" ~ page ~ (has_limit ? "&limit=" ~ limit : "") ~ "&info=Updated role successfully");
	scope(failure) output.addHeader("Location", "/admin/users?page=" ~ page ~ (has_limit ? "&limit=" ~ limit : "") ~ "&error=Failed to update role");
	scope(exit) output.status = 302;
	
	enforce(["is_admin", "is_trusted", "is_deactivated"].canFind(request.get.read("role")), "invalid role");

	scope Database db = new Database(environment["db_filename"]);
	Stmt stmt = db.prepare_bind!(string, string)("UPDATE users SET " ~ request.get.read("role") ~ " = ?
																										WHERE user_id = ?",
                                               request.get.read("value"), request.get.read("id"));
	db.exec(stmt);	
}
