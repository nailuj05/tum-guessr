module game;

import serverino;

@endpoint @route!("/game")
void game(Request request, Output output) {
	output.serveFile("public/game.html");
}
