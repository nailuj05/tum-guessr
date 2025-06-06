module app;

import std.ascii : LetterCase;
import std.stdio;
import std.format;
import std.algorithm;
import std.file;
import std.getopt;
import std.range;
import std.logger;
import std.conv;
import std.digest : toHexString;
import std.uni : toLower;
import std.process : environment;
import std.string : representation;
import session;
import std.path;
import std.datetime;
import std.datetime.systime;

import serverino;
import mustache;
import dotenv;

import sqlite;
import logger;

import upload;
import login;
import profile;
import game;
import admin;
import photos;
import report;
import header;
import stats;

mixin ServerinoMain!(upload, login, profile, game, admin, photos, report, stats);

alias MustacheEngine!(string) Mustache;

@onServerInit ServerinoConfig configure(string[] args)
{	
  bool showHelp = false;
	bool verbose = false;
	bool unsafe = false;
  int num_populate_users = 0;
	string db_filename = "prod.db";
	
	scope(failure) 
	{
		writeln("Usage: ", baseName(args[0]), " [OPTIONS]");
    writeln("Options:");
    writeln("  --help                       Show this help message.");
    writeln("  --verbose                    Enable verbose output.");
    writeln("  --unsafe                     Enable unsafe static cookie hmac, less strict pwds, no captchas (for debugging)");
    writeln("  --populate_users=NUM_USERS   Populate table users with NUM_USERS random generated users. Password is set to 'pw'.");
    writeln("  --database=FILE              Path to database file.");
		ServerinoConfig.create().setReturnCode(1);
	}

	showHelp = getopt(args,
										"verbose",  &verbose,
										"unsafe",   &unsafe,
                    "populate_users", &num_populate_users,
										"database", &db_filename)
		.helpWanted;
	
	environment["verbose"] = verbose.to!string;
	environment["unsafe"] = unsafe.to!string;
	environment["db_filename"] = db_filename;

  Env.load();
  environment["CAPTCHA_SECRET_KEY"] = Env["CAPTCHA_SECRET_KEY"];
  
	if(!exists("photos"))
		 mkdir("photos");

	if(!exists("logs"))
		 mkdir("logs");

	// Rename old logfile
	string original = "logs/log.txt";
	if(exists(original)) {
		auto now = Clock.currTime();
		string timeStr = now.toISOString();
		rename(original, "logs/log_" ~ timeStr ~ ".txt");
	}

  // need to reload the file logger after moving file
  flogger_reload();
  
	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE
      | OpenFlags.CREATE);
  try {
    db.exec_imm("CREATE TABLE IF NOT EXISTS users (
      user_id INTEGER PRIMARY KEY, 
      username TEXT NOT NULL UNIQUE, 
      password_hash TEXT NOT NULL,
      sign_up_time INTEGER NOT NULL,
      is_admin INTEGER NOT NULL DEFAULT FALSE,
      is_trusted INTEGER NOT NULL DEFAULT FALSE,
      is_deactivated INTEGER NOT NULL DEFAULT FALSE
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS photos ( 
      photo_id INTEGER PRIMARY KEY, 
      path TEXT NOT NULL UNIQUE,  
      latitude REAL NOT NULL, 
      longitude REAL NOT NULL,
      location STRING NOT NULL,
      uploader_id INTEGER NOT NULL, 
      upload_time INTEGER NOT NULL,
      FOREIGN KEY(uploader_id) 
        REFERENCES users(user_id) 
          ON DELETE CASCADE 
          ON UPDATE CASCADE
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS photo_acceptances (
      photo_id INTEGER PRIMARY KEY,
      acceptor_id INTEGER NOT NULL,
      acceptance_time INTEGER NOT NULL,
      FOREIGN KEY(photo_id)
        REFERENCES photos(photo_id)
          ON DELETE CASCADE 
          ON UPDATE CASCADE,
      FOREIGN KEY(acceptor_id)
        REFERENCES users(user_id)
          ON DELETE CASCADE 
          ON UPDATE CASCADE
    )");
		db.exec_imm("DROP VIEW IF EXISTS photos_with_acceptance");
    db.exec_imm("CREATE VIEW IF NOT EXISTS photos_with_acceptance AS
        SELECT p.*,
            CASE
                WHEN pa.photo_id IS NOT NULL THEN 1
                ELSE 0
            END AS is_accepted
        FROM photos p
        LEFT JOIN photo_acceptances pa ON p.photo_id=pa.photo_id
    ");
		db.exec_imm("CREATE TABLE IF NOT EXISTS games (
      game_id INTEGER PRIMARY KEY,
      user_id INTEGER NOT NULL,
      location TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON DELETE CASCADE 
          ON UPDATE CASCADE
    )");
		db.exec_imm("CREATE TABLE IF NOT EXISTS rounds (
      round_id INTEGER NOT NULL,
      game_id INTEGER NOT NULL,
      photo_id INTEGER NOT NULL,
      duration INTEGER NOT NULL,
      PRIMARY KEY (round_id, game_id),
      FOREIGN KEY(game_id) 
        REFERENCES games(game_id) 
          ON DELETE CASCADE
          ON UPDATE CASCADE,
      FOREIGN KEY(photo_id)
        REFERENCES photos(photo_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE
    )");
		db.exec_imm("CREATE TABLE IF NOT EXISTS timing (
      round_id INTEGER NOT NULL,
      game_id INTEGER NOT NULL,
      start_time INTEGER NOT NULL,
			PRIMARY KEY (round_id, game_id),
      FOREIGN KEY(round_id, game_id) 
        REFERENCES rounds(round_id, game_id) 
          ON DELETE CASCADE
          ON UPDATE CASCADE
    )");
    db.exec_imm("CREATE TABLE IF NOT EXISTS guesses (
      round_id INTEGER NOT NULL,
      game_id INTEGER NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      score INTEGER NOT NULL,
      PRIMARY KEY (round_id, game_id),
      FOREIGN KEY(round_id, game_id) 
        REFERENCES rounds(round_id, game_id) 
          ON DELETE CASCADE
          ON UPDATE CASCADE
    )");
		db.exec_imm("DROP VIEW IF EXISTS started_rounds");
		db.exec_imm("CREATE VIEW IF NOT EXISTS started_rounds AS
      SELECT *
      FROM rounds r
      JOIN timing t
      USING (round_id, game_id)
    ");
		db.exec_imm("DROP VIEW IF EXISTS timed_out_rounds");
		db.exec_imm("CREATE VIEW IF NOT EXISTS timed_out_rounds AS
      SELECT s.*
      FROM started_rounds s
      LEFT JOIN guesses g
      USING (round_id, game_id)
      WHERE g.round_id IS NULL
        AND (start_time + duration) <= CAST(strftime('%s', 'now') AS INTEGER)
    ");
		db.exec_imm("DROP VIEW IF EXISTS guessed_rounds");
		db.exec_imm("CREATE VIEW IF NOT EXISTS guessed_rounds AS
      SELECT *
      FROM rounds
      JOIN guesses
      USING (round_id, game_id)
    ");
		db.exec_imm("DROP VIEW IF EXISTS finished_rounds");
    db.exec_imm("CREATE VIEW IF NOT EXISTS finished_rounds AS
      SELECT r.round_id, r.game_id, r.photo_id, r.duration, r.score, FALSE AS has_timed_out 
      FROM guessed_rounds r
      UNION
      SELECT r.round_id, r.game_id, r.photo_id, r.duration, 0 AS score, TRUE AS has_timed_out
      FROM timed_out_rounds r
    ");
		db.exec_imm("DROP VIEW IF EXISTS unfinished_rounds");
    db.exec_imm("CREATE VIEW IF NOT EXISTS unfinished_rounds AS
      SELECT r.*
      FROM rounds r
      LEFT JOIN finished_rounds f
      USING (round_id, game_id)
      WHERE f.round_id IS NULL
    ");
    db.exec_imm("CREATE TABLE IF NOT EXISTS reports (
      report_id INTEGER PRIMARY KEY,
      user_id INTEGER NOT NULL,
      report_text TEXT NOT NULL,
      photo_id INTEGER NOT NULL,
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON UPDATE CASCADE
      FOREIGN KEY(photo_id)
        REFERENCES photos(photo_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE
    )");
		db.exec_imm("
      INSERT OR IGNORE INTO users (user_id, username, password_hash, sign_up_time, is_deactivated)
      VALUES (0, 'unknown', '', 0, 1)
    ");
    db.exec_imm("CREATE TABLE IF NOT EXISTS statistic (
      timestamp INTEGER NOT NULL,
      user_id INTEGER,
      device TEXT NOT NULL,
      referrer TEXT NOT NULL,
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON UPDATE CASCADE
          ON DELETE SET NULL
    )");

    if (num_populate_users > 0) {
      populate_users(num_populate_users);
    }
  } catch (Database.DBException e){
    string error = "An exception occurred during database initialization: "~e.msg;
    flogger.error(error);
    writeln(error);
  }

  flogger.info("SERVER STARTED");
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@onDaemonStart
void daemon_start() {
	ubyte[64] random_bytes;
	if (!environment["unsafe"].to!bool) random_bytes = cast(ubyte[])read("/dev/urandom", 64);
	environment["cookie_hmac_key"] = random_bytes.toHexString!(LetterCase.lower);
}

@endpoint @route!("/") @route!(r => r.path.startsWith("/index"))
void index(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");

	scope auto mustache_context = new Mustache.Context;
	
  set_header_context(mustache_context, request, output);

	int[] milestones = [10, 25, 50, 100, 250, 500, 750, 1000, 1500, 2000, 3000, 5000];
	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
	int users = db.query_imm!(int)("SELECT COUNT(*) FROM users")[0][0];
	int photos = db.query_imm!(int)("SELECT COUNT(*) FROM photos")[0][0];

	int nextBigger(int[] arr, int num) {
		int i = 0;
    do i++;
		while (arr[i] < num && i < (arr.length - 1));
		return arr[i];
	}
	mustache_context["user_cur"] = users;
	mustache_context["user_max"] = nextBigger(milestones, users);
	mustache_context["photo_cur"] = photos;
	mustache_context["photo_max"] = nextBigger(milestones, photos);

	output ~= mustache.render("index", mustache_context);
}

@endpoint @route!("/about")
void about(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  
  set_header_context(mustache_context, request, output);
	output ~= mustache.render("about", mustache_context);
}

@endpoint @priority(-1)
void router(Request request, Output output) {
	string path = "public" ~ request.path;

	// if we don't want to use serveFile we will need to set the mime manually (check the code for serveFile for a good example on that)
	string[] ftypes = [".js", ".css", ".ico", ".png", ".jpg", ".jpeg", ".ico", ".txt"];
	if(exists(path) && ftypes.any!(suffix => path.endsWith(suffix))) {
		if (environment["verbose"] == true.to!string)
				flogger.info("Router served resource at " ~ path);
		output.serveFile(path);
  } else {
    flogger.warning("Router refused to serve resource at " ~ path);
	}
}

@endpoint @priority(-10)
void page404(Output output)
{
	// Set the status code to 404
	output.status = 404;
	output.addHeader("Content-Type", "text/plain");

	output.write("Page not found!");
}

void populate_users(int num_users, string password = "pw") {
  import passwd;
  import passwd.bcrypt;
  string password_hash = to!(string)(password.crypt(Bcrypt.genSalt()));
	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
  db.exec(db.prepare_bind("
  WITH RECURSIVE iterator(n) AS (
    SELECT 1
    UNION ALL
    SELECT n+1 FROM iterator WHERE n < ?
  )
  INSERT OR IGNORE INTO users (username, password_hash)
  SELECT
    'user_' || ABS(RANDOM()), ?
  FROM iterator
  ", num_users, password_hash));
}
