module session;
import std.ascii : LetterCase;
import std.logger;
import serverino.interfaces;
import std.digest.hmac;
import std.digest.sha;
import std.digest : toHexString, fromHexString;
import std.uni : toLower;
import std.process : environment;
import std.file;
import std.conv;
import std.string : representation;
import core.time;
import std.datetime;
import std.regex;

import sqlite;

// saves user_id and expiration to cookie
void session_save(ref Output output, int user_id, Duration maxAge = 15.minutes)
{
		bool verbose = environment["verbose"].to!bool;
		long expiration = Clock.currTime.toUnixTime + maxAge.total!"seconds";
		ubyte[] hmac_key = environment["cookie_hmac_key"].fromHexString;
		string cookie_info = to!string(user_id) ~ ":" ~ to!string(expiration);
		string hmac = cookie_info.representation.hmac!SHA256(hmac_key).toHexString!(LetterCase.lower).dup;
		string session_cookie = cookie_info ~ ":" ~ hmac;
		if (verbose)
			info("Setting cookie: " ~ session_cookie);
		output.setCookie(Cookie("session", session_cookie).httpOnly(true));
}

// returns user_id on success
// returns -1 otherwise
int session_load(const Request request, ref Output output)
{
		bool verbose = environment["verbose"].to!bool;
		string session_cookie = request.cookie.read("session");
		if (verbose)
				info("Loading session with cookie: " ~ session_cookie);
		auto match = matchFirst(session_cookie, ctRegex!`^((\d+):(\d+)):([0-9a-f]+)$`);
		
		if (!match) {
			warning("Cookie has invalid format: " ~ session_cookie);
			session_remove(output);
			return -1;
		}

		string cookie_info = match[1];
		string cookie_hmac = match[4];
		if (verbose) {
			info("Cookie info: " ~ cookie_info);
			info("Cookie hmac: " ~ cookie_hmac);
		}

		ubyte[] hmac_key = environment["cookie_hmac_key"].fromHexString;
		string hmac = cookie_info.representation.hmac!SHA256(hmac_key).toHexString!(LetterCase.lower).dup;

		if (cookie_hmac != hmac) {
			warning("Cookie " ~ session_cookie ~ " has invalid hmac: { expected: " ~ hmac ~ ", got: " ~ cookie_hmac ~ " }");
			session_remove(output);
			return -1;
		}


		int user_id = to!int(match[2]);
		long expiration = to!long(match[3]);
		if (verbose) {
			info("Cookie hmac OK");
			info("Cookie user_id: " ~ to!string(user_id));
			info("Cookie expiration: " ~ to!string(expiration));
		}

		if (expiration < Clock.currTime.toUnixTime) {
			if (verbose)
				warning("Session expired, removing");
			session_remove(output);
			return -1;
		}

		if (verbose)
				info("Session loaded successfully");
		
		return user_id;
}

void session_remove(ref Output output)
{
	bool verbose = environment["verbose"].to!bool;
	if (verbose)
		info("Removing cookie");
	output.setCookie(Cookie("session", "invalid").httpOnly(true).invalidate());
}
