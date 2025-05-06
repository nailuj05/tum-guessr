module app;

import std;
import simplesession;
import serverino;

mixin ServerinoMain;

@endpoint @route!("/")
void index(Request request, Output output) {
  SimpleSession session = SimpleSession(request, output, 60.minutes);
  JSONValue session_data = session.load();
  // retrieve and set session data here
  session.save(session_data);

  output.serveFile("public/index.html");
}
