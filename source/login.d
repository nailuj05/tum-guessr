module login;

import std.conv;
import std.format;
import std.array;
import std.file;
import std.datetime;
import std.regex;
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
    if (!request.post.has("username") ||
        !request.post.has("password") ||
        !request.post.has("h-captcha-response")) {
      output.status = 400;
      output ~= "Missing argument";
      return;
    }
    const string username = request.post.read("username");
    const string password = request.post.read("password");
    const string captcha  = request.post.read("h-captcha-response");

		const string username_regex = `.+`;
		const string password_regex = environment["unsafe"].to!bool ? `.+` : `.{16,}`;
		
		if (!matchFirst(username, username_regex.regex)) {
			output.status = 400;
			mustache_context.addSubContext("error_messages")["error_message"] = "Username must match regex /" ~ username_regex ~ "/";
			output ~= mustache.render("sign_up", mustache_context);
			return;
		}
		if (!matchFirst(password, password_regex.regex)) {
			output.status = 400;
			mustache_context.addSubContext("error_messages")["error_message"] = "Password must match regex /" ~ password_regex ~"/";
			mustache_context.useSection("password_xkcd");
			output ~= mustache.render("sign_up", mustache_context);
			return;
		}

    // Verify Captcha Response
    import std.net.curl;
    auto url = "https://api.hcaptcha.com/siteverify";
    auto postData = "secret=" ~ environment["CAPTCHA_SECRET_KEY"] ~ "&response=" ~ captcha;

    auto response = post(url, postData);
    
    import std.json;
    JSONValue json = parseJSON(response);
    if(json["success"].type == JSON_TYPE.FALSE) {
      flogger.warning("Sign up captcha failed for user: ", username, " with ", response);

      output.status = 400;
			mustache_context.addSubContext("error_messages")["error_message"] = "Captcha failed";
			output ~= mustache.render("sign_up", mustache_context);
			return;
    }

    
    // Add to DB
	  scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
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
		long timestamp = Clock.currTime.toUnixTime;
    
    db.exec(db.prepare_bind!(string, string, long)("
        INSERT INTO users (username, password_hash, sign_up_time)
        VALUES (?, ?, ?)
      ", username, password_hash, timestamp));

    int user_id = db.query!(int)(db.prepare_bind!string("
        SELECT user_id
        FROM users
        WHERE username=?
      ", username))[0][0];

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
    if (!request.post.has("username") ||
        !request.post.has("password")) {
      output.status = 400;
      output ~= "Missing username or password";
      return;
    }
    string username = request.post.read("username");
    string password = request.post.read("password");


	  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
    auto query_result = db.query!(int, string, int)(db.prepare_bind!(string)("
      SELECT user_id, password_hash, is_deactivated 
      FROM users
      WHERE username=?
    ", username));
    
    if (query_result.length > 0) {
      int user_id = query_result[0][0];
      string password_hash = query_result[0][1];
			int deactivated = query_result[0][2];

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
		scope(failure) flogger.error("Database error when logging out");
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

// TODO: Debug endpoint, remove before production
@endpoint @route!"/delete_me"
void delete_user(Request request, Output output) {
	int user_id = session_load(request, output);
	if (user_id < 0) {
		output.status = 302;
		output.addHeader("Location", "/login");
		output ~= "Not logged in";
		return;
	}
	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
	try {
		db.exec(db.prepare_bind("DELETE FROM users WHERE user_id=?", user_id));
	} catch (Database.DBException e) {
		flogger.warning("Something went wrong during user deletion: " ~ e.msg);
	}
	
	output ~= "Successfully deleted yourself";
}
