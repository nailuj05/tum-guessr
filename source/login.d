module login;

import std.conv;
import std.format;
import std.array;
import std.file;
import serverino;
import passwd;
import passwd.bcrypt;
import std.logger;
import std.process : environment;

import mustache;

import sqlite;
import session;
import logger;

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

	  scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
    if (db.query!(int)(db.prepare_bind!(string)("
      SELECT count(*) 
      FROM users
      WHERE email=?
    ", email))[0][0] > 0) {
      output.status = 400;
		  mustache_context.addSubContext("error_messages")["error_message"] = "Email already in use";
			output ~= mustache.render("sign_up", mustache_context);
      return;
    }
    if (db.query!(int)(db.prepare_bind!(string)("
      SELECT count(*) 
      FROM users
      WHERE username=?
    ", username))[0][0] > 0) {
      output.status = 400;
		  mustache_context.addSubContext("error_messages")["error_message"] = "Username already in use";
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

    flogger.info("User " ~ to!string(user_id) ~ " aka '" ~ username ~ "' signed up.");

    session_save(output, user_id);

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

	  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
    auto query_result = db.query!(int, string, string, int)(db.prepare_bind!(string, string)("
      SELECT user_id, username, password_hash, isDeactivated 
      FROM users
      WHERE email=? OR username=?
    ", email_or_username, email_or_username));
    
    if (query_result.length > 0) {
      int user_id = query_result[0][0];
			string username = query_result[0][1];
      string password_hash = query_result[0][2];
			int deactivated = query_result[0][3];

      if (deactivated == 0 && password.canCryptTo(password_hash)) {
				session_save(output, user_id);
        flogger.info("User " ~ to!string(user_id) ~ " aka '" ~ username ~ "' logged in.");

        output.status = 302;
        output.addHeader("Location", "/");
        output ~= "Logged in successfully!" ~ "\n" ~ "You are being redirected.";
        return;
      }
    }

    output.status = 400;
		mustache_context.addSubContext("error_messages")["error_message"] = "Wrong username or password";
    output ~= mustache.render("login", mustache_context);
    return;
  }
  output.status = 405;
}

@endpoint @route!("/logout")
void logout(Request request, Output output) {
  int user_id = session_load(request, output);
	session_remove(output);

  if (user_id > 0) {
    scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
    string username = db.query!string(db.prepare_bind!int("
      SELECT username
      FROM users
      WHERE user_id=?    
    ", user_id))[0][0];
    flogger.info("User " ~ to!string(user_id) ~ " aka '" ~ username ~ "' logged out.");
  } else {
    flogger.info("User attempted logout without being logged in.");
  }
	
	output.status = 302;
	output.addHeader("Location", "/");
	output ~= "Logged out!" ~ "\n" ~ "You are being redirected.";
}
