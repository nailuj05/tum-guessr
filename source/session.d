module session;
import serverino.interfaces;
import std;

import sqlite;

// TODO: set cookie path, domain, secure, httpOnly, sameSite as needed
struct Session
{
   static string safeSessionID(uint length = 32)
   {
      ubyte[] value = new ubyte[length];
      value[0..$] = cast(ubyte[])read("/dev/urandom", value.length);
      return value.toHexString.toLower;
   }

   this(const Request r, ref Output o, string databaseFilename, Duration maxAge = 15.minutes)
   {
      output = &o;

      _session_id = r.cookie.read("session_id");
      _databaseFilename = databaseFilename;
      _isNew = _session_id.length == 0;
      _maxAge = maxAge;

      if (_isNew) _session_id = safeSessionID();
   }

   string id() { return _session_id; }

   // saves user_id and expiration to database
   void save(int user_id)
   {
      long expiration = Clock.currTime.toUnixTime + _maxAge.total!"seconds";

      scope Database db = new Database(_databaseFilename);
      db.exec(db.prepare_bind!(string)("
        DELETE FROM sessions
        WHERE session_id=?
      ", _session_id));

      db.exec(db.prepare_bind!(string, int, long)("
        INSERT INTO sessions (session_id, user_id, expiration)
        VALUES (?, ?, ?)
      ", _session_id, user_id, expiration));

      if (_isNew)
         output.setCookie(Cookie("session_id", _session_id).httpOnly(true));
   }
   
   // checks expiration and loads user_id from database
   // returns user_id on success
   // returns -1 otherwise
   int load()
   {
      try
      {
          scope Database db = new Database(_databaseFilename);
          auto query_result = db.query!(int, long)(db.prepare_bind!(string)("
            SELECT user_id, expiration
            FROM sessions
            WHERE session_id=?
          ", _session_id));    
          if (query_result.length < 1) {
            warning("Session not found");
            return -1;
          }
          int user_id = query_result[0][0];
          long expiration = query_result[0][1];
          if (expiration < Clock.currTime.toUnixTime)
          {
             warning("Session expired, removing");
             remove();
             return -1;
          }
          return user_id;
      }
      catch(Exception e) { warning("Error loading session, removing."); remove(); }
      return -1;
   }

   void remove()
   {
      output.setCookie(Cookie("session_id", _session_id).httpOnly(true).invalidate());

      _session_id = safeSessionID();
      _isNew = true;
   }

   bool isNew()   { return _isNew; }

   private:

   Output      *output;
   string      _databaseFilename; 
   Duration    _maxAge;
   string      _session_id;
   bool        _isNew = true;
}
