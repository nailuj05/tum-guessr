module app;

import std;
import std.stdio;
import std.format;
import std.file;
import simplesession;
import serverino;
import core.sync.mutex;
import passwd;
import passwd.bcrypt;

import sqlite;
import upload;

mixin ServerinoMain!(upload);


@onServerInit ServerinoConfig configure(string[] args)
{
	scope Database db = new Database("test.db");
  try {
    db.exec_imm("CREATE TABLE IF NOT EXISTS users (
      user_id INTEGER PRIMARY KEY, 
      email TEXT NOT NULL UNIQUE, 
      username TEXT NOT NULL UNIQUE, 
      password_hash TEXT NOT NULL,
      isAdmin INTEGER NOT NULL DEFAULT FALSE   
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS photos ( 
      photo_id INTEGER PRIMARY KEY, 
      path TEXT NOT NULL UNIQUE,  
      latitude REAL NOT NULL, 
      longitude REAL NOT NULL, 
      user_id INTEGER, 
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON DELETE SET NULL 
          ON UPDATE CASCADE 
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS sessions ( 
      session_token INTEGER PRIMARY KEY, 
      user_id INTEGER NOT NULL, 
      expiration INTEGER NOT NULL, 
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id)  
          ON DELETE CASCADE 
          ON UPDATE CASCADE 
    )");
  } catch (Database.DBException e){
    writeln("An exception occurred during database initialization: ", e.msg);
  }
      
	db.exec_imm("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, line TEXT)");
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@endpoint @route!("/sign_up")
void sign_up(Request request, Output output) {
  if (request.method == Request.Method.Get) {
    output.serveFile("public/sign_up.html");
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
      output ~= "Email already exists";
      return;
    }
    if (db.query!(int)(db.prepare_bind!(string)("
      SELECT count(*) 
      FROM users
      WHERE username=?
    ", username))[0][0] > 0) {
      output.status = 400;
      output ~= "Username already exists";
      return;
    }

    string password_hash = to!(string)(password.crypt(Bcrypt.genSalt()));
    
    auto insert_user_stmt = db.prepare_bind!(string, string, string)("
        INSERT INTO users (email, username, password_hash)
        VALUES (?, ?, ?)
      ", email, username, password_hash);
    db.exec(insert_user_stmt);

    output.status = 302;
    output.addHeader("Location", "/");
    output ~= "Signed up successfully!" ~ "\n" ~ "You are being redirected.";
    return;
  }
  output.status = 405;
}

@endpoint @route!("/login")
void login(Request request, Output output){
  if (request.method == Request.Method.Get) {
    output.serveFile("public/login.html");
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
        output.status = 302;
        output.addHeader("Location", "/");
        output ~= "Logged in successfully!" ~ "\n" ~ "You are being redirected.";
        return;
      }
    }

    output.status = 400;
    output ~= "Wrong email_or_username or password";
    return;
  }
  output.status = 405;
}

@endpoint @route!("/data")
void data(Request request, Output output)
{
	output ~= "Data:<br>";
	
	scope Database db = new Database("test.db", OpenFlags.READONLY);
	auto rows = db.query_imm!(int, string)("SELECT * FROM test");
	foreach (row; rows) {
		string f = format("%d: %s", row[0], row[1]);
		output ~= f ~ "<br>";
	}
}

@endpoint
void router(Request request, Output output) {
	string path = "public";
	if(request.path == "/")
		path ~= "/index.html";
	else
		path ~= request.path;

	// if we don't want to use serve File we will need to set the mime manually (check the code for serveFile for a good example on that)
	if(exists(path))
		output.serveFile(path);
}

@endpoint @priority(-1)
void page404(Output output)
{
	// Set the status code to 404
	output.status = 404;
	output.addHeader("Content-Type", "text/plain");

	output.write("Page not found!");
}
