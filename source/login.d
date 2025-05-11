module login;

import std.conv;
import std.format;
import std.array;
import std.file;
import serverino;
import passwd;
import passwd.bcrypt;

import sqlite;
import session;
import mustache;

alias MustacheEngine!(string) Mustache;

@endpoint @route!("/sign_up")
void sign_up(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  if (request.method == Request.Method.Get) {
    output ~= mustache.render("sign_up", mustache_context);
    return;
  } else if (request.method == Request.Method.Post){
    if (!request.post.has("username") || !request.post.has("email") ||
        !request.post.has("password")) {
      output.status = 400;
      output ~= "Missing argument";
      return;
    }
    string email = request.post.read("email");
    string username = request.post.read("username");
    string password = request.post.read("password");


	  scope Database db = new Database("test.db", OpenFlags.READWRITE);
    if (db.query!(int)(db.prepare_bind!(string)("
      SELECT count(*) 
      FROM users
      WHERE email=?
    ", email))[0][0] > 0) {
      output.status = 400;
      mustache_context["error_message"] = "Email already in use";
			output ~= mustache.render("sign_up", mustache_context);
      return;
    }
    if (db.query!(int)(db.prepare_bind!(string)("
      SELECT count(*) 
      FROM users
      WHERE username=?
    ", username))[0][0] > 0) {
      output.status = 400;
      mustache_context["error_message"] = "Username already in use";
			output ~= mustache.render("sign_up", mustache_context);
      return;
    }

    string password_hash = to!(string)(password.crypt(Bcrypt.genSalt()));
    
    db.exec(db.prepare_bind!(string, string, string)("
        INSERT INTO users (email, username, password_hash)
        VALUES (?, ?, ?)
      ", email, username, password_hash));

    int user_id = db.query!(int)(db.prepare_bind!(string, string, string)("
        SELECT user_id
        FROM users
        WHERE email=? AND username=? AND password_hash=?
      ", email, username, password_hash))[0][0];

    Session session = Session(request, output, "test.db");
    session.save(user_id);

    output.status = 302;
    output.addHeader("Location", "/");
    output ~= "Signed up successfully!" ~ "\n" ~ "You are being redirected.";
    return;
  }
  output.status = 405;
}

@endpoint @route!("/login")
void login(Request request, Output output){
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  Session session = Session(request, output, "test.db");
  if (request.method == Request.Method.Get) {
    output ~= mustache.render("login", mustache_context);
    return;
  } else if (request.method == Request.Method.Post) {
    if (!request.post.has("email_or_username") ||
        !request.post.has("password")) {
      output.status = 400;
      output ~= "Missing email_or_username or password";
      return;
    }
    string email_or_username = request.post.read("email_or_username");
    string password = request.post.read("password");

	  scope Database db = new Database("test.db", OpenFlags.READWRITE);
    auto query_result = db.query!(int, string)(db.prepare_bind!(string, string)("
      SELECT user_id, password_hash 
      FROM users
      WHERE email=? OR username=?
    ", email_or_username, email_or_username));
    
    if (query_result.length > 0) {
      int user_id = query_result[0][0];
      string password_hash = query_result[0][1];

      if (password.canCryptTo(password_hash)) {
        session.save(user_id);
        output.status = 302;
        output.addHeader("Location", "/");
        output ~= "Logged in successfully!" ~ "\n" ~ "You are being redirected.";
        return;
      }
    }

    output.status = 400;
    mustache_context["error_message"] = "Wrong Username or Password";
    output ~= mustache.render("login", mustache_context);
    return;
  }
  output.status = 405;
}

@endpoint @route!("/logout")
void logout(Request request, Output output) {
	import std.experimental.logger;
  Session session = Session(request, output, "test.db");
	session.remove();

	info("user logged out");
	
	output.status = 302;
	output.addHeader("Location", "/");
	output ~= "Logged out!" ~ "\n" ~ "You are being redirected.";
}
