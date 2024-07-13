/// The main module, contains basic SDL boilerplate
module texed.app;

import std.path, std.file, std.string, std.format;

import texed.event, texed.state, texed.sdl, texed.types, texed.ui, texed.misc, texed.locale;

enum TARGET_FPS = 60; /// Target frames per second
enum TARGET_TPF = 1000 / TARGET_FPS; /// Target ticks per frame

/// The current state. THIS SHOULD ALMOST NEVER BE USED DIRECTLY. If you need the state, pass it into your function.
///
/// The only exceptions are when changing the state, for ex. when loading a project.
State currentState;

/// The entrypoint
int main() {
	// setup directories if not present
	if(!projDir.exists)
		mkdir(projDir);
	else if(!projDir.isDir) {
		remove(projDir);
		mkdir(projDir);
	}
	// initialize sdl
	if(SDL_Init(SDL_INIT_VIDEO) < 0)
		throw new SDLException();
	if(Mix_Init(MIX_INIT_OGG) < 0)
		throw new SDLException();
	if(Mix_OpenAudio(44100, AUDIO_S16SYS, 2, 512))
		throw new SDLException();
	// initialize locales
	initLocales();
	// create window
	auto sdlWindow = SDL_CreateWindow(
		locale["misc.title"].format(TEXED_VERSION).toStringz, 
		SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 
		1280, 720, 
		SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
	);
	if(!sdlWindow)
		throw new SDLException();
	auto sdlRenderer = SDL_CreateRenderer(sdlWindow, -1, SDL_RENDERER_ACCELERATED);
	if(!sdlRenderer)
		throw new SDLException();
	SDL_SetRenderDrawBlendMode(sdlRenderer, SDL_BLENDMODE_BLEND);
	auto window = new DesktopWindow(sdlRenderer, sdlWindow);
	Font.loadBackupFont(window);
	currentState = new State(window);
	currentState.init();

	int lastTick = 0; // tick used for fps correction

	// start event loop
	outer: while(true) {
		try {
			SDL_Event e;
			while(SDL_PollEvent(&e)) {
				switch(e.type) {
					case SDL_QUIT:
						break outer;
					default:
						currentState.handleEvent(&e);
						break;
				}
			}
			currentState.update();
			SDL_SetRenderDrawColor(window.rend, 0, 0, 0, 255);
			SDL_RenderClear(window.rend);
			currentState.render();
			SDL_RenderPresent(window.rend);

			// correct fps
			int ticks = SDL_GetTicks()-lastTick;
			if(ticks < TARGET_TPF)
				SDL_Delay(TARGET_TPF-ticks);
			lastTick = SDL_GetTicks();
		} catch(Exception e) {
			currentState.error(e);
		}
	}
	return 0;
}
