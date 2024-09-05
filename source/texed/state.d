/// Contains the state class, associated classes, and most runtime logic
module texed.state;

import std.algorithm, std.datetime.stopwatch, std.array, std.conv, std.variant, std.path, std.file, std.utf, std.format, std.process, std.stdio, std.string;

import texed.event, texed.types, texed.sdl, texed.misc, texed.ui, texed.action, texed.project, texed.locale;

/// Stores global state and state information
final class State {
	enum size_t CHANNEL_COUNT = 2; /// Number of channels

	// State
	DesktopWindow window; /// The window

	View cameraView; /// Camera view
	View editorView; /// Editor view
	float zoomPower = 6; /// Zoom power. Used to set `editorView.zoom`
	
	View currentView; /// Current view (set to one of the views above)
	
	Font font; /// Current font

	float currTime = 0; /// Current time
	StopWatch stopWatch; /// Stopwatch used for measuring time
	bool paused = true; /// Whether the state is paused

	StopWatch lastSavedStopwatch; /// Counts time since last saved
	

	Window[] windows; /// Currently open windows
	Window[string] defaultWindows; /// Windows that can't be closed, saved here for easy access

	Grabbable grabbed = null; /// Currently grabbed object.
	Selectable selected = null; /// Currently selected object.
	Placeable toPlace = null; /// Object to place.
	/// [SceneGrabbable] info before grabbing
	Variant anteSceneGrabbableInfo;

	// free clickables
	Grabbable backgroundGrabbable; /// Background grabbable; used for scrolling
	Grabbable timeSliderGrabbable; /// Grabbable for the time slider


	Theme theme = Theme.DARK; /// Current theme

	float snap = 1.0; /// How much to snap to grid

	Action[] actions; /// Actions performed
	size_t actionPos; /// Where we are in `actions`

	Audio audio; /// The current audio file

	bool ctrlHeld; /// Whether control is currently held

	Color foregroundColor = Color(255, 255, 255, 255); /// Current foreground color
	Color backgroundColor = Color(0, 0, 0, 0); /// Current background color

	Image missingImage; /// Image to be used when an image can not be found

	string lastSavedName = ""; /// Name of last saved project

	// Project Data
	/// Events, organized by channel
	Event[][CHANNEL_COUNT] events;
	string name = ""; /// Project name
	string audioPath = ""; /// Audio file name

	
	///
	this(DesktopWindow window) {
		this.window = window;
		cameraView = new View(Vector!float(1280, 720));
		int width, height;
		SDL_GetWindowSize(window.win, &width, &height);
		editorView = new View(Vector!float(width, height));
		currentView = editorView;
		// TODO: customizable font
		font = new Font([
			0x00: Image.load(window, buildPath(exeDir, "assets", "font_0000.png")), 
			0x02: Image.load(window, buildPath(exeDir, "assets", "font_0200.png")),
			0x03: Image.load(window, buildPath(exeDir, "assets", "font_0300.png")),
			0x1F: Image.load(window, buildPath(exeDir, "assets", "font_1f00.png"))
		], 10);	
		missingImage = Image.load(window, buildPath(exeDir, "assets", "missing.png"));
		// init background grabbable
		backgroundGrabbable = new class Grabbable {
			Vector!float dragPos; /// drag position
			Vector!float oldEditorTrans; /// Old editor translation	

			ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
				if(button == MouseButton.MIDDLE)
					return ClickResponse.GRAB;
				return ClickResponse.PASS;
			}

			void clicked(State state, MouseButton button, Vector!int mouse) {}
			void grabbed(State state, Vector!int mouse) {
				dragPos = mouse.to!float;
				oldEditorTrans = state.editorView.translation;
			}
			void grabMove(State state, Vector!int mouse) {
				state.editorView.translation = oldEditorTrans+(dragPos-mouse.to!float)/state.editorView.zoom;
			}
		};
		// init time slider grabbable
		timeSliderGrabbable = new class Grabbable {
			ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
				if(state.timeRect.contains(mouse))
					return state.paused && button == MouseButton.MIDDLE ? ClickResponse.GRAB : ClickResponse.CLICK;
				return ClickResponse.PASS;
			}

			void clicked(State state, MouseButton button, Vector!int mouse) {}
			void grabbed(State state, Vector!int mouse) {}
			void grabMove(State state, Vector!int mouse) {
				if(!state.paused)
					return;
				auto rect = state.timeRect;
				// inverse lerp
				float t = texed.misc.clamp((cast(float)(mouse.x-rect.pos.x))/(cast(float)(rect.size.x)), 0f, 1f);
				currTime = t*audio.duration;
			}
		};
		lastSavedStopwatch.setTimeElapsed(5.seconds);
		lastSavedStopwatch.start();
	}
	
	/// Initializes the state. 
	void init() {
		loadAudio(true);
		createWindows();
	}

	void createWindows() {
		auto wColors = new Window(locale["window.colors.title"], Rect!int(30, 30, 300, 120), false, null);
		wColors.widget = new VBox(1,
			new Label(0.25, 16, locale["window.colors.foreground"]),
			new ColorSelector(0.25, "foreground", 16, foregroundColor),
			new Label(0.25, 16, locale["window.colors.background"]),
			new ColorSelector(0.25, "background", 16, backgroundColor),
			new ScriptableWidget!Nothing(0, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
				// update colors
				foregroundColor = wColors.get!ColorSelector("foreground").color;
				backgroundColor = wColors.get!ColorSelector("background").color;
			})
		);
		windows ~= wColors;
		defaultWindows["colors"] = wColors;
		windows ~= new Window(locale["window.events.title"], Rect!int(30, 180, 150, 300), false, new VBox(1,
			new Button(0.2, 16, locale["window.events.text"], {
				toPlace = new TextEvent(Vector!float(0, 0), currTime, float.infinity, foregroundColor, backgroundColor, 1.0, "");
			}),
			new Button(0.2, 16, locale["window.events.camera"], {
				auto lastCamera = cast(CameraEvent)lastFired(1, currTime);
				float zoom = lastCamera is null ? View.DEFAULT_ZOOM : lastCamera.post.zoom;
				toPlace = new CameraEvent(currTime, currTime+1.0, "easeOutCubic", Vector!float(0, 0), zoom, Vector!float(0, 0), zoom);
			}),
			new Button(0.2, 16, locale["window.events.image"], {
				toPlace = new ImageEvent(currTime, float.infinity, Vector!float(0, 0), 1, "");
			}),
			new Button(0.2, 16, locale["window.events.box"], {
				toPlace = new BoxEvent(currTime, float.infinity, Vector!float(0, 0), Vector!int(3, 3), 1, foregroundColor, backgroundColor);
			}),
		));
		auto wProject = new Window(locale["window.project.title"], Rect!int(950, 30, 330, 300), false, null);
		wProject.widget = new VBox(1,
			new Label(0.1, 16, locale["window.project.name"]),
			new TextEdit(0.1, "project-name", 16, name, locale["window.project.name"]),
			new Label(0.1, 16, locale["window.project.audio"]),
			new TextEdit(0.1, "project-audio", 16, audioPath, locale["window.project.audio"]),
			new Button(0.1, 16, locale["window.project.save"], { save(); }),
			new HBar(0.05, 20, ThemeColor.PRIMARY),
			new Label(0.1, 16, locale["window.project.name"]),
			new TextEdit(0.1, "name-to-load", 16, name, locale["window.project.project-to-load"]),
			new Button(0.1, 16, "Load", {
				try {
					loadProject(wProject.get!TextEdit("name-to-load").text, window);
				} catch(ProjectException e) {
					error(e, locale["error.while-loading"]);
				}
			}),
			new HBar(0.05, 20, ThemeColor.PRIMARY),
			new Button(0.1, 12, locale["window.project.open-directory"], {
				openFileManager(projDir(name));
			}),
			new Button(0.1, 16, locale["window.project.render"], {
				yesno(locale["window.project.render-confirm"], locale["ui.confirm"], {
					renderVideo();
				}, {});
			})
		);
		windows ~= wProject;
		defaultWindows["project"] = wProject;
	}

	/// Handles an event
	void handleEvent(SDL_Event* e) {
		switch(e.type) {
			case SDL_MOUSEWHEEL: {
				if(!inEditor)
					break;
				// zoom in/out
				auto evt = e.wheel;
				zoomPower += evt.y < 0 ? -0.5 : 0.5;
				editorView.zoom = 2^^zoomPower;
				break;
			}
			case SDL_WINDOWEVENT: {
				auto evt = e.window;
				switch(evt.event) {
					case SDL_WINDOWEVENT_RESIZED:
						// window resized; editorView should change its screen size
						editorView.screenSize = Vector!float(evt.data1, evt.data2);
						break;
					default:
						break;
				}
				break;
			}
			// mouse events
			case SDL_MOUSEBUTTONDOWN: {
				if(!inEditor)
					break;
				auto evt = e.button;
				auto button = buttonFromIndex(evt.button);
				auto mousePos = Vector!int(evt.x, evt.y);
				if(ctrlHeld) {
					switch(button) {
						case MouseButton.RIGHT:
							// delete
							foreach(c; collectClickables()) {
								auto response = c.mouseClick(this, button, mousePos);
								switch(response) {
									case ClickResponse.PASS:
										break;
									default:
										// remove, if relevant
										if(auto p = cast(Placeable)c) {
											perform(new RemoveAction(p));
										}
										return;
								}
							}
							return;
						case MouseButton.MIDDLE:
							// clone
							foreach(c; collectClickables()) {
								auto response = c.mouseClick(this, button, mousePos);
								if(auto cloneable = cast(Cloneable)c) {
									switch(response) {
										case ClickResponse.GRAB: {
											// clone and grab
											auto clone = cloneable.clone(this);
											if(auto eventClone = cast(Event)clone) {
												// set start to current time, since that's more intuitive
												eventClone.start = currTime;
												// this is needed because events will usually only know their bounding box after they get rendered.
												timeEvent(eventClone, playTime); 
											}
											anteSceneGrabbableInfo = null; // don't try to create a GrabAction for this event
											clone.grabbed(this, mousePos);
											selected = null;
											grabbed = clone;
											perform(new PlaceAction(clone));
											break;
										}
										default:
											break;
									}
								}
							}
							return;
						default:
							break;
					}
				}
				// place object if there is one to place
				if(button == MouseButton.LEFT && toPlace !is null) {
					if(auto event = cast(Event)toPlace) {
						auto lf = lastFired(event.channel, currTime);
						if(lf !is null && event.channel != 0 && (lf.end >= currTime || (currTime+event.end >= lf.start && currTime+event.start <= lf.end))) {
							error(locale["error.only-one-active-per-channel"]);
							toPlace = null;
							return;
						}
					}
					perform(new PlaceAction(toPlace));
					if(auto sel = cast(Selectable)toPlace)
						selected = sel;
					toPlace = null;
					return;
				}
				foreach(c; collectClickables()) {
					auto response = c.mouseClick(this, button, mousePos);
					final switch(response) {
						case ClickResponse.GRAB:
							c.clicked(this, button, mousePos);
							if(auto g = cast(Grabbable)c) {
								if(auto win = cast(Window)g) {
									// move window to top
									foreach(i, w; windows)
										if(w == win) {
											windows = windows[0..i]~windows[i+1..$];
											break;
										}
									windows = win~windows;
								}
								if(auto sg = cast(SceneGrabbable)g) {
									// set scene grabbable info
									anteSceneGrabbableInfo = sg.getGrabInfo();
								}
								selected = null;
								grabbed = g;
								g.grabbed(this, mousePos);
								return;
							}
							return;
						case ClickResponse.SELECT:
							if(auto s = cast(Selectable)c) {
								grabbed = null;
								selected = s;
								s.clicked(this, button, mousePos);
							}
							return;
						case ClickResponse.CLICK:
							grabbed = null;
							selected = null;
							c.clicked(this, button, mousePos);
							return;
						case ClickResponse.BLOCK:
							grabbed = null;
							selected = null;
							return;
						case ClickResponse.PASS:
							break;
					}
				}
				grabbed = null;
				selected = null;
				break;
			}
			case SDL_MOUSEBUTTONUP: {
				auto evt = e.button;
				auto button = buttonFromIndex(evt.button);
				if(grabbed !is null) {
					if(auto sg = cast(SceneGrabbable)grabbed) {
						if(anteSceneGrabbableInfo != null)
							perform(new GrabAction(sg, anteSceneGrabbableInfo, sg.getGrabInfo()));
						anteSceneGrabbableInfo = null;
					}
					grabbed = null;
				}
				switch(button) {
					default:
						break;
				}
				break;
			}
			case SDL_KEYDOWN: {
				auto evt = e.key;
				auto keysym = evt.keysym;
				if(keysym.sym == SDLK_ESCAPE) {
					// stop selecting
					if(selected !is null)
						selected = null;
					// stop placing
					if(toPlace !is null)
						toPlace = null;
				}
				if(keysym.sym == SDLK_LCTRL)
					ctrlHeld = true;
				if(inEditor && selected !is null && (selected.listens & Listen.KEY)) {
					selected.input(this, new KeyEvent(evt.keysym));
					return;
				}
				switch(keysym.sym) {
					case SDLK_z:
						if(!inEditor)
							break;
						if(keysym.mod & KMOD_CTRL) {
							// undo/redo
							if(keysym.mod & KMOD_SHIFT)
								redo();
							else
								undo();
						}
						break;
					case SDLK_SPACE:
						// paused/unpause
						pause(!paused);
						if(paused)
							currentView = editorView;
						else if(keysym.mod & KMOD_LCTRL)
							currentView = cameraView;
						break;
					case SDLK_s:
						if(!inEditor)
							break;
						if(keysym.mod & KMOD_CTRL)
							// save
							save();
						break;
					case SDLK_PERIOD:
						// unadvance(?) time
						if(!inEditor)
							break;
						currTime += 0.1;
						break;
					case SDLK_COMMA:
						// advance time
						if(!inEditor)
							break;
						currTime -= 0.1;
						break;
					case SDLK_LEFT:
						if(!inEditor)
							break;
						currTime -= 1.0;
						break;
					case SDLK_RIGHT:
						if(!inEditor)
							break;
						currTime += 1.0;
						break;
					case SDLK_v:
						// swap view
						currentView = currentView == editorView ? cameraView : editorView;
						break;
					default:
						break;
				}
				break;
			}
			case SDL_KEYUP: {
				if(e.key.keysym.sym == SDLK_LCTRL)
					ctrlHeld = false;
				break;
			}
			case SDL_TEXTINPUT: {
				auto evt = e.text;
				if(selected !is null) {
					auto str = evt.text.ptr.to!string.toUTF32;
					selected.input(this, new CharacterEvent(str[0]));
				}
				break;
			}
			default:
				break;

		}

	}
	
	/// Updates the state
	void update() {
		auto mousePos = mouse();
		// updated grabbed object
		if(grabbed !is null)
			grabbed.grabMove(this, mousePos);
		// remove closed windows
		windows = windows.filter!(x => !x.closeClicked).array;
		// stop playing if over time
		float time = playTime();
		if(audio !is null && time >= audio.duration) {
			if(!paused) {
				pause(true);
				currentView = editorView;
			}
			if(currTime >= audio.duration)
				currTime = audio.duration;
		}
	}

	private void timeEvent(Event evt, float time) {
		float rel = (time-evt.start)/(evt.end-evt.start), abs = time-evt.start;
		evt.time(this, rel, abs);
	}

	private void timeEvent(Event evt) {
		timeEvent(evt, playTime);
	}

	/// Renders the scene
	void render() {
		float time = playTime();
		// render channel 0 events
		foreach(evt; events[0]) {
			if(time >= evt.start && time <= evt.end)
				timeEvent(evt, time);
		}
		// render other events
		for(size_t i = 1; i < CHANNEL_COUNT; i++) {
			auto last = lastFired(i, time);
			if(last is null) {
				if(i == 1) {
					// set camera view to default
					// yeah this is hardcoding and bad but I'm not sure what else to do here
					cameraView.translation = View.DEFAULT_TRANSLATION;
					cameraView.zoom = View.DEFAULT_ZOOM;
				}
				continue;
			}
			timeEvent(last);
		}

		if(inEditor) {
			// render camera box
			{
				theme.secondary.draw(window.rend);
				auto size = cameraView.screenSize/cameraView.zoom;
				auto rect = editorView.transform(Rect!float(cameraView.translation-size/2, size)).toSDL();
				SDL_RenderDrawRectF(window.rend, &rect);
			}
			// render time slider
			if(audio !is null) {
				auto rect = timeRect();
				theme.foreground.draw(window.rend);
				// render |-|
				SDL_RenderDrawLine(window.rend, rect.pos.x, rect.pos.y, rect.pos.x, rect.pos.y+rect.size.y);
				SDL_RenderDrawLine(window.rend, rect.pos.x+rect.size.x, rect.pos.y, rect.pos.x+rect.size.x, rect.pos.y+rect.size.y);
				SDL_RenderDrawLine(window.rend, rect.pos.x, rect.pos.y+rect.size.y/2, rect.pos.x+rect.size.x, rect.pos.y+rect.size.y/2);
				// render heads
				theme.primary.draw(window.rend);
				int x = lerp(rect.pos.x, rect.pos.x+rect.size.x, currTime/audio.duration);
				SDL_RenderDrawLine(window.rend, x, rect.pos.y, x, rect.pos.y+rect.size.y);
				if(time != currTime) {
					theme.secondary.draw(window.rend);
					x = lerp(rect.pos.x, rect.pos.x+rect.size.x, time/audio.duration);
					SDL_RenderDrawLine(window.rend, x, rect.pos.y, x, rect.pos.y+rect.size.y);
				}
				// render time text
				string timeText = format(locale["misc.time-slider"].format((time/60).to!int, (time%60).to!int, format("%.2f", time)));
				font.render(window.rend, theme.foreground, Color.TRANSPARENT, null, Vector!float(rect.pos.x+rect.size.x/2-timeText.length*10, rect.pos.y-20), 20, timeText);
				// render "Saved!" text
				if(lastSavedStopwatch.peek < 500.msecs)
					font.render(window.rend, theme.foreground, Color.TRANSPARENT, null, Vector!float(rect.pos.x, rect.pos.y-20), 20, locale["misc.saved"]);
			}
			// render windows
			foreach_reverse(w; windows)
				w.render(this);
			// render & update placeable
			if(toPlace !is null) {
				toPlace.placeMove(this, mouse());
				toPlace.preview(this);
			}
		} else {
			// draw bars
			if(cameraView.screenSize != editorView.screenSize) {
				auto ss = editorView.screenSize;
				auto diff = ss-cameraView.screenSize;
				auto rightRect = SDL_FRect(ss.x-diff.x, 0, diff.x, ss.y);
				auto bottomRect = SDL_FRect(0, ss.y-diff.y, ss.x, diff.y);
				SDL_SetRenderDrawColor(window.rend, 128, 128, 128, 255);
				SDL_RenderFillRectF(window.rend, &rightRect);
				SDL_RenderFillRectF(window.rend, &bottomRect);
			}
		}

		
	}

	/// Adds an event
	void addEvent(Event e) {
		auto channel = e.channel;
		events[channel] ~= e;
		sortChannel(channel); // make sure events are sorted by end time
	}

	/// Sorts a given channel
	void sortChannel(size_t channel) {
		events[channel].sort!"a.start < b.start";
	}

	/// Sorts all channels
	void sortAllChannels() {
		for(size_t i = 0; i < CHANNEL_COUNT; i++)
			sortChannel(i);
	}

	/// Removes an event
	void removeEvent(Event e) {
		auto channel = e.channel;
		size_t idx = events[channel].countUntil(e);
		events[channel] = events[channel][0..idx]~events[channel][idx+1..$]; // removing won't mess up the sort order
	}

	/// Pauses or unpauses
	void pause(bool newPaused) {
		if(audio is null && newPaused == false) {
			error(locale["error.must-load-audio"]);
			return;
		}
		paused = newPaused;
		if(paused) {
			stopWatch.stop();
			stopWatch.reset();
			if(audio !is null)
				audio.pause();
		} else {
			stopWatch.start();
			if(audio !is null) {
				audio.seek(currTime);
				audio.play();
			}
		}
	}
	
	/// Determines whether we're currently in the editor
	@property bool inEditor() {
		return currentView == editorView;
	}

	/// Sets whether we're in the editor
	@property void inEditor(bool value) {
		if(value) {
			currentView = editorView;
		} else {
			currentView = cameraView;
		}
	}

	/// Gets all clickables in the scene
	Clickable[] collectClickables() {
		Clickable[] ret;
		foreach(w; windows) {
			ret ~= w.collectClickables();
			ret ~= w;
		}
		ret ~= timeSliderGrabbable;
		foreach_reverse(channel; events) {
			// reversed so that events that render ontop will be grabbed ontop
			foreach_reverse(e; channel) {
				if(auto clickable = cast(Clickable)e)
					ret ~= clickable;
			}
		}
		ret ~= backgroundGrabbable;
		return ret;
	}

	/// Gets the current mouse position
	Vector!int mouse() {
		int x, y;
		SDL_GetMouseState(&x, &y);
		return Vector!int(x, y);
	}
	
	/// Performs an action. If `perform` is true, then additionally `action.perform` is called.
	void perform(Action action, bool perform = true) {
		if(actionPos != actions.length)
			actions = actions[0..actionPos];
		actions ~= action;
		actionPos++;
		if(perform)
			action.perform(this);
	}

	/// Undoes the last action
	void undo() {
		if(actionPos == 0)
			return;
		actions[--actionPos].undo(this);
	}

	/// Redoes the next action
	void redo() {
		if(actionPos >= actions.length)
			return;
		actions[actionPos++].perform(this);
	}

	/// Opens an error box
	void error(string text, string title = "error.title", uint flags = SDL_MESSAGEBOX_ERROR) {
		// auto win = new Window(locale[title], Rect!int((editorView.screenSize/2).to!int-Vector!int(cast(int)text.length*7, 50), Vector!int(cast(int)text.length*15, 100)), true, null);
		// win.widget = new VBox(1,
		// 	new Label(0.75, 14, tc, text),
		// 	new Button(0.25, 16, locale["error.ok"], {
		// 		win.closeClicked = true;
		// 	})
		// );
		// windows = win~windows;
		SDL_ShowSimpleMessageBox(flags, locale[title].toStringz, text.toStringz, window.win);
	}

	/// Opens an error box for the given exception and prints it to the console
	void error(Exception exception, string title = "error.title", ThemeColor tc = ThemeColor.ERROR) {
		error(exception.msg, title, tc);
		import std.stdio;
		writeln(exception);
	}
	
	/// Opens an info box
	void info(string text, string title = "ui.info") {
		// error(text, title, ThemeColor.FOREGROUND);
		error(text, title, SDL_MESSAGEBOX_INFORMATION);
	}
	
	/// Opens a yes/no dialogue box
	void yesno(string text, string title, void delegate() yes, void delegate() no) {
		auto win = new Window(title, Rect!int((editorView.screenSize/2).to!int-Vector!int(cast(int)text.length*7, 50), Vector!int(cast(int)text.length*15, 100)), true, null);
		win.widget = new VBox(1,
			new Label(0.75, 14, text),
			new HBox(0.25,
				new Button(0.5, 16, locale["ui.yes"], {
					win.closeClicked = true;
					yes();
				}),
				new Button(0.5, 16, locale["ui.no"], {
					win.closeClicked = true;
					no();
				}),
			)
		);
		windows = win~windows;
	}

	/// Loads audio
	void loadAudio(bool suppressError = false) {
		try {
			audio = new Audio(buildPath(projDir(name), audioPath));
		} catch(AudioNotFoundException e) {
			if(!suppressError)
				error(e, locale["error.loading-audio"]);
		} catch(SDLException e) {
			error(e, locale["error.loading-audio"]);
		}
	}

	/// render rectangle for the time scroll widget
	Rect!int timeRect() {
		auto size = editorView.screenSize.to!int;
		enum xspacing = 50;
		enum yspacing = 20;
		enum height = 50;
		return Rect!int(xspacing, size.y-height-yspacing, size.x-2*xspacing, height);
	}

	/// Opens a window
	void openWindow(Window win, bool center = true) {
		if(center)
			win.rect.pos = editorView.screenSize.to!int/2-win.rect.size/2;
		windows = win~windows;
	}

	/// Gets the last fired event on a given channel at a given time, or null if none
	Event lastFired(size_t channel, float time) {
		foreach_reverse(evt; events[channel]) {
			if(evt.start <= time)
				return evt;
		}
		return null;
	}

	/// Gets the current playing time
	float playTime() => currTime+stopWatch.peek.total!"msecs"/1000f;

	void save() {
		name = defaultWindows["project"].get!TextEdit("project-name").text;
		try {
			saveProject(this);
		} catch(ProjectException e) {
			error(e, locale["error.while-saving"]);
		}
		lastSavedStopwatch.reset();
	}

	void renderVideo() {
		// audio should exist
		if(audio is null) {
			error(locale["error.need-audio-before-rendering"]);
			return;
		}
		// check if ffmpeg exists before doing anything else
		// TODO: check ffmpeg version
		{
			try {
				int status = execute(["ffmpeg", "--help"]).status;
				if(status != 0) {
					error(locale["error.no-ffmpeg"]);
					return;
				}
			} catch(ProcessException) {
				error(locale["error.no-ffmpeg"]);
				return;
			} catch(StdioException) {
				error(locale["error.no-ffmpeg"]);
				return;
			}
		}
		// create images directory
		string dir = projDir(name);
		string imgDir = buildPath(dir, "images");
		if(imgDir.exists)
			rmdirRecurse(imgDir);
		mkdir(imgDir);
		scope(exit)
			rmdirRecurse(imgDir);

		// render, and take control of the event loop from main()
		currentView = cameraView;
		scope(exit)
			currentView = editorView;
		enum FPS = 30f; // TODO: make this configurable
		int frameCount = 0;
		stopWatch.stop();
		stopWatch.reset();
		
		SDL_RestoreWindow(window.win);
		SDL_SetWindowSize(window.win, cast(int)cameraView.screenSize.x, cast(int)cameraView.screenSize.y);
		editorView.screenSize = cameraView.screenSize; // make sure editor view doesn't get bugged out after rendering
		SDL_Surface* frameSurface = SDL_CreateRGBSurface(0, cast(int)(cameraView.screenSize.x), cast(int)(cameraView.screenSize.y), 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000);
		outer: while(true) {
			try {
				SDL_Event e;
				while(SDL_PollEvent(&e)) {
					switch(e.type) {
						case SDL_QUIT:
							return;
						default:
							// ignore event
							break;
					}
				}
				// render frame
				currTime = (1/FPS)*frameCount;
				if(currTime > audio.duration)
					break outer;
				update();
				SDL_SetRenderDrawColor(window.rend, 0, 0, 0, 255);
				SDL_RenderClear(window.rend);
				render();
				SDL_RenderPresent(window.rend);

				// save image
				SDL_RenderReadPixels(window.rend, null, SDL_PIXELFORMAT_ARGB8888, frameSurface.pixels, frameSurface.pitch);
				if(IMG_SavePNG(frameSurface, buildPath(imgDir, "%08d.png").format(frameCount).toStringz) != 0)
					throw new SDLException();
				
				frameCount++;
			} catch(Exception e) {
				error(e);
				return;
			}
		}
		// display "running ffmpeg..."
		SDL_SetRenderDrawColor(window.rend, 0, 0, 0, 255);
		SDL_RenderClear(window.rend);
		font.render(window.rend, theme.foreground, theme.background, null, Vector!float(0, 0), 20, locale["misc.running-ffmpeg"]);
		SDL_RenderPresent(window.rend);

		// create video with ffmpeg
		string output = buildPath(dir, "output.webm");
		{
			auto ffmpeg = execute(["ffmpeg", "-framerate", "30", "-y", "-i", dir~"/images/%08d.png", "-i", buildPath(dir, audioPath), output]);
			if(ffmpeg.status != 0) {
				writeln(ffmpeg.output);
				error(locale["error.ffmpeg-failed"].format(ffmpeg.status));
				return;
			}
		}
		info(locale["misc.render-complete"].format(output));
	}
}
