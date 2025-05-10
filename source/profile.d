module profile;

import serverino;
import sqlite;
import session;
import mustache;
import std.regex;
import std.algorithm;

alias MustacheEngine!(string) Mustache;

@endpoint @route!"/profile"
void profile(Request request, Output output) {
  if (request.method != Request.Method.Get) {
    output.status = 405;
    return;
  }
  Session session = Session(request, output, "test.db");
  int session_user_id = session.load();
  if (session_user_id < 0) {
    output.status = 302;
    output.addHeader("Location", "/login");
    return;
  }

  scope Database db = new Database("test.db");
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

  scope Database db = new Database("test.db");
  auto query_result = db.query!(int, string)(db.prepare_bind!(string)("
    SELECT user_id, email
    FROM users
    WHERE username=?
  ", username));

  if (query_result.length < 1) {
    output.status = 404;
    output ~= "Profile does not exist";
    return;
  }

  int user_id = query_result[0][0];
  string email = query_result[0][1];

  Session session = Session(request, output, "test.db");
  int session_user_id = session.load();

  Mustache mustache;
  mustache.ext("html");
  scope auto mustache_context = new Mustache.Context;
  mustache_context["username"] = username;
  if (session_user_id == user_id) {
    mustache_context.useSection("logged_in");
    mustache_context["email"] = email;    
  }
  output ~= mustache.render("public/profile", mustache_context);
}
