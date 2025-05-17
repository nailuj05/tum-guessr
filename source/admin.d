module admin;

import std.algorithm;
import std.conv;
import std.file;
import std.logger;
import std.array;
import std.process : environment;

import serverino;
import mustache;

import sqlite;
import session;
import logger;

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
    flogger.warning("Unknown user attempted admin access without valid session.");
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

@endpoint @route!"/admin"
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
  
  int limit = to!int(request.get.read("limit", "30"));
  int offset = to!int(request.get.read("offset", "0"));

  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  auto query_result = db.query!(int, string, int, int, int)(db.prepare_bind!(int, int)("
    SELECT user_id, username, is_admin, is_trusted, is_deactivated
    FROM users
    ORDER BY user_id
    LIMIT ? OFFSET ?  
  ", limit, offset));

  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;

  foreach (ref row; query_result) {
    auto mustache_subcontext = mustache_context.addSubContext("users");
    mustache_subcontext["user_id"] = row[0];
    mustache_subcontext["username"] = row[1];
    mustache_subcontext["is_admin"] = row[2];
		// TODO add admin_checkbox here
  }

	if (request.get.has("error")) {
		mustache_context.addSubContext("error_messages")["error_message"] = request.get.read("error");
	} else if (request.get.has("info")) {
		mustache_context.addSubContext("info_messages")["info_message"] = request.get.read("info");
	}
	
  output ~= mustache.render("admin_users", mustache_context);
}

@endpoint @route!"/admin/log"
void admin_log(Request request, Output output) {
  if (request.method != Request.Method.Get) {
    output.status = 405;
  }
	
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
	mustache_context["log"] = readText("logs/log.txt");
	
	output ~= mustache.render("admin_log", mustache_context);
}

@endpoint @route!(r => r.path == "/admin/set" && r.get.has("id") && r.get.has("role") && r.get.has("value"))
void set_role(Request r, Output output) {
  if (r.method != Request.Method.Get) {
    output.status = 405;
  }

	scope(success) output.addHeader("Location", "/admin/users?info=Updated role successfully");
	scope(failure) output.addHeader("Location", "/admin/users?error=Failed to update role");
	scope(exit) output.status = 302;
	
	assert(["is_admin", "is_trusted", "is_deactivated"].canFind(r.get.read("role")), "invalid role");

	scope Database db = new Database(environment["db_filename"]);
	Stmt stmt = db.prepare_bind!(string, string)("UPDATE users SET " ~ r.get.read("role") ~ " = ?
                                                    WHERE user_id = ?",
																										r.get.read("value"), r.get.read("id"));
	db.exec(stmt);	
}
