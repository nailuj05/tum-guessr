module profile;

import std.regex;
import std.algorithm;
import std.process : environment;
import std.datetime : SysTime;
import std.format;

import mustache;
import serverino;

import sqlite;
import session;
import logger;
import header;

alias MustacheEngine!(string) Mustache;

@endpoint @route!"/profile"
void profile(Request request, Output output) {
  if (request.method != Request.Method.Get) {
    output.status = 405;
    return;
  }
  
  int session_user_id = session_load(request, output);
  if (session_user_id < 0) {
    output.status = 302;
    output.addHeader("Location", "/login");
    return;
  }

  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  auto query_result = db.query!(string)(db.prepare_bind!(int)("
    SELECT username
    FROM users
    WHERE user_id=?
  ", session_user_id));

  if (query_result.length < 1) {
    output.status = 302;
    output.addHeader("Location", "/login");
    return;
  }

  string username = query_result[0][0];
  output.status = 302;
  output.addHeader("Location", "/profile/" ~ username);
}

@endpoint @route!(request => request.path.startsWith("/profile/"))
void profile_username(Request request, Output output) {
  if (request.method != Request.Method.Get) {
    output.status = 405;
    return;
  }

  auto username_match = matchFirst(request.path, ctRegex!(`^/profile/(\w+)$`));
  if (username_match.empty) {
    output.status = 404;
    output ~= "Profile does not exist";
    return;
  }

  string username = username_match[1];

  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  auto query_result = db.query!(int, int)(db.prepare_bind!(string)("
    SELECT user_id, sign_up_time
    FROM users
    WHERE username=?
  ", username));

  if (query_result.length < 1 || username == "unknown") {
    output.status = 404;
    output ~= "Profile does not exist";
    return;
  }

  int user_id = query_result[0][0];
  int sign_up_time = query_result[0][1];

  int session_user_id = session_load(request, output);

  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  mustache_context["username"] = username;
  set_header_context(mustache_context, request, output);
  
  auto dateTime = SysTime.fromUnixTime(sign_up_time);
  mustache_context["join_date"] = format("%02d-%02d-%04d", dateTime.day, dateTime.month, dateTime.year);

  auto games_played    = db.query!(int)(db.prepare_bind!(int)("SELECT COUNT(*) FROM games WHERE user_id = ?", user_id))[0][0];
  auto photos_uploaded = db.query!(int)(db.prepare_bind!(int)("SELECT COUNT(*) FROM photos WHERE uploader_id = ?", user_id))[0][0];

  mustache_context["games_played"] = games_played;
  mustache_context["photos_uploaded"] = photos_uploaded;
  
  output ~= mustache.render("profile", mustache_context);
}
