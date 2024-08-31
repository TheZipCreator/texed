/// Contains code that deals with events
module texed.event;

import std.conv, std.variant, std.json, std.utf, std.typecons, std.math, std.path, std.array;

import texed.state, texed.types, texed.ui, texed.sdl, texed.locale, texed.misc;

/// Class all events inherit from
abstract class Event {
	float start; /// When the event should appear
	float end; /// When the event should disappear (Infinity if event never deactivates)

	this(float start, float end) {
		this.start = start;
		this.end = end;
	}	

	/** 
		Called every frame, both in editor and while playing. For channel 0 events,
		this is called only when the event is active; for events on other channels,
		in the time period between when the event becomes active, and when the next
		event of the channel becomes active.
	
		`rel` ∈ [0, 1] while the frame is active, 0 representing first time the event is visible, 1 representing the last time.
		
		`abs` is the amount of seconds since the event has become active.

	*/
	void time(State state, float rel, float abs) {}

	/// Gets the channel this event falls under. Whenever using a new channel, increment `CHANNEL_COUNT` in the `State` class.
	///
	/// With the exception of channel #0, only one event per channel may be active at a time.
	size_t channel() => 0;

	/// Does extra initialization after the state is initialized.
	void postInit(State state) {}
}

/// A grabbable thing in the scene
interface SceneGrabbable : Grabbable {
	Variant getGrabInfo(); /// Gets information that was changed after a grab
	void setGrabInfo(Variant var); /// Sets the information the was changed after a grab
}

/// Any cloneable event (must also be a [SceneGrabbable])
interface Cloneable : SceneGrabbable, Placeable {
	Cloneable clone(State state); /// Clones the event
}

/// A text event
class TextEvent : Event, Selectable, Placeable, SceneGrabbable, Cloneable {
	mixin TextEditor!(true);

	Vector!float pos; /// Position of text
	float fontSize; /// Font size of the text
	Color fg; /// Foreground color
	Color bg; /// Background color

	// state
	private Rect!int rect; /// Click rect
	private Vector!int grabbedPos; /// Where this event was grabbed from

	
	///
	this(Vector!float pos, float start, float end, Color fg, Color bg, float fontSize, string text) {
		super(start, end);
		this.pos = pos;
		this.fg = fg;
		this.bg = bg;
		this.fontSize = fontSize;
		this.text = text;
		cursorPos = (text.to!dstring).length;
	}
	
	/// Render function used in both `time` and `preview`.
	void render(State state, Color col, bool cursor = false) {
		rect = state.font.render(state.window.rend, col, bg, state.currentView, pos, fontSize, text == "" ? locale["event.text.missing"] : text, cursor ? cursorPos : size_t.max).to!int;
	}
	
	///
	override void time(State state, float rel, float abs) {
		if(state.inEditor && state.selected == this) {
			state.theme.primary.draw(state.window.rend);
			auto sdlRect = rect.toSDL();
			SDL_RenderDrawRect(state.window.rend, &sdlRect);
			render(state, fg, true);
			return;
		}
		render(state, fg, state.inEditor && state.selected == this);
	}
	
	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(state.playTime < start || state.playTime > end)
			return ClickResponse.PASS;
		if(rect.contains(mouse)) {
			if(button == MouseButton.LEFT)
				return ClickResponse.SELECT;
			else if(button == MouseButton.RIGHT)
				return ClickResponse.CLICK;
			if(button == MouseButton.MIDDLE)
				return ClickResponse.GRAB;
			return ClickResponse.BLOCK;
		}
		return ClickResponse.PASS;
	}
	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		if(button == MouseButton.RIGHT) {
			// open object window
			Window win;
			float maxTime = state.audio is null ? float.infinity : state.audio.duration;
			win = new Window(locale["event.text.title"], Rect!int(0, 0, 300, 300), true, new VBox(1,
				new Label(0.1, 16, locale["event.start-time"]),
				new NumberEdit!float(0.1, "start-time", 16, 0.0, maxTime, 0.1, start),
				new Label(0.1, 16, locale["event.end-time"]),
				new NumberEdit!float(0.1, "end-time", 16, 0.0, float.infinity, 0.1, end),
				new Label(0.1, 16, locale["event.font-size"]),
				new NumberEdit!float(0.1, "font-size", 16, 1.0, float.infinity, 0.1, fontSize),
				new Label(0.1, 16, locale["event.foreground"]),
				new ColorSelector(0.1, "foreground", 16, fg),
				new Label(0.1, 16, locale["event.background"]),
				new ColorSelector(0.1, "background", 16, bg),
				new ScriptableWidget!Nothing(0, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
					// update text properties
					// TODO: make this undoable
					start = win.get!(NumberEdit!float)("start-time").value;
					end = win.get!(NumberEdit!float)("end-time").value;
					fontSize = win.get!(NumberEdit!float)("font-size").value;
					fg = win.get!ColorSelector("foreground").color;
					bg = win.get!ColorSelector("background").color;
				})
			));
			state.openWindow(win);
		}
		// TODO: change text editing cursor position to match mouse position
	}

	///
	int listens() => Listen.CHARACTER | Listen.KEY;
	
	///
	void input(State state, InputEvent evt) {
		editText(state, evt);
	}

	///
	void preview(State state) {
		render(state, fg.withAlpha(128));
	}

	///
	void placeMove(State state, Vector!int mouse) {
		pos = state.currentView.invTransform(mouse.to!float).snap(state.snap);
	}

	///
	void place(State state) {
		state.addEvent(this);
	}

	///
	void remove(State state) {
		state.removeEvent(this);
	}

	///
	Variant getGrabInfo() => Variant(pos);

	///
	void setGrabInfo(Variant var) {
		pos = var.get!(Vector!float);
	}

	///
	void grabbed(State state, Vector!int mouse) {
		grabbedPos = mouse-rect.pos;
	}

	///
	void grabMove(State state, Vector!int mouse) {
		pos = state.currentView.invTransform((mouse-grabbedPos).to!float).snap(state.snap);
	}

	///
	Cloneable clone(State state) => new TextEvent(pos, start, end, fg, bg, fontSize, text);
}

/// Moves or zooms the camera
class CameraEvent : Event, Placeable, SceneGrabbable, Cloneable {
	private enum TRANS_RECT_SIZE = 2.5;
	private enum ZOOM_RECT_BORDER = 10;

	string easing; /// Easing to use
	/// State of a view
	private struct ViewState {
		Vector!float translation; /// Translation
		float zoom; /// Zoom
		Rect!int transRect; /// Rectangle where the box is to drag translation
		Region!int zoomRegion; /// Region of the border that displays zoom
		
		/// Renders the viewstate
		void render(State state) {
			auto rend = state.window.rend;
			transRect = state.currentView.transform(Rect!float(translation-TRANS_RECT_SIZE/2, Vector!float(TRANS_RECT_SIZE, TRANS_RECT_SIZE))).to!int;
			auto sdlTransRect = transRect.toSDL();
			SDL_RenderDrawRect(rend, &sdlTransRect);
			Vector!float size = state.cameraView.screenSize/zoom;
			auto zoomRect = state.currentView.transform(Rect!float(translation-size/2, size)).to!int;
			auto sdlZoomRect = zoomRect.toSDL();
			SDL_RenderDrawRect(rend, &sdlZoomRect);
			auto border = Vector!int(ZOOM_RECT_BORDER/2, ZOOM_RECT_BORDER/2);
			auto bottom = zoomRect.pos+zoomRect.size;
			zoomRegion.rects = [
				Rect!int.fromPoints(zoomRect.pos-border, Vector!int(bottom.x, zoomRect.pos.y)+border),
				Rect!int.fromPoints(zoomRect.pos-border, Vector!int(zoomRect.pos.x, bottom.y)+border),
				Rect!int.fromPoints(Vector!int(bottom.x, zoomRect.pos.y)-border, bottom+border),
				Rect!int.fromPoints(Vector!int(zoomRect.pos.x, bottom.y)-border, bottom+border)
			];
		}

		/// Gets the region
		Region!int region() => zoomRegion.join(transRect);

		/// Gets the center
		Vector!int center() => transRect.pos+transRect.size/2;
	}
	ViewState ante; /// State before
	ViewState post; /// State after

	/// Grab state
	private bool grabbedPost, grabbedZoom;
	private Vector!int grabbedPos;

	this(float start, float end, string easing, Vector!float anteTranslation, float anteZoom, Vector!float postTranslation, float postZoom) {
		super(start, end);
		this.easing = easing;
		ante = ViewState(anteTranslation, anteZoom);
		post = ViewState(postTranslation, postZoom);
	}
	
	// render the thing to show in the editor
	private void render(State state, int alphaDiv) {
		auto rend = state.window.rend;
		state.theme.foreground.withAlpha(128/alphaDiv).draw(rend);
		ante.render(state);
		state.theme.foreground.withAlpha(255/alphaDiv).draw(rend);
		post.render(state);
	}
	
	///
	override void time(State state, float rel, float abs) {
		if(state.inEditor && abs <= end-start)
			render(state, 1);
		if(rel >= 1f) {
			state.cameraView.translation = post.translation;
			state.cameraView.zoom = post.zoom;
			return;
		}
		float x = ease(easing, rel); // ease time value
		// set camera attributes
		state.cameraView.translation = ante.translation.lerp(post.translation, x);
		state.cameraView.zoom = lerp(ante.zoom, post.zoom, x);
	}
	
	///
	override size_t channel() => 1;

	///
	void preview(State state) {
		render(state, 2);
	}

	///
	void placeMove(State state, Vector!int mouse) {
		ante.translation = state.currentView.invTransform(mouse.to!float).snap(state.snap);
		post.translation = ante.translation+Vector!float(50, 0).snap(state.snap);
	}

	///
	void place(State state) {
		state.addEvent(this);
	}

	///
	void remove(State state) {
		state.removeEvent(this);
	}

	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(state.playTime < start || state.playTime > end)
			return ClickResponse.PASS;
		if(ante.region.join(post.region).contains(mouse))
			return button == MouseButton.MIDDLE ? ClickResponse.GRAB : ClickResponse.CLICK;
		return ClickResponse.PASS;
	}

	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		if(button == MouseButton.RIGHT) {
			// open object window
			Window win;
			float maxTime = state.audio is null ? float.infinity : state.audio.duration;
			win = new Window(locale["event.camera.title"], Rect!int(0, 0, 300, 300), true, new VBox(1,
				new Label(0.1, 16, locale["event.start-time"]),
				new NumberEdit!float(0.1, "start-time", 16, 0.0, maxTime, 0.1, start),
				new Label(0.1, 16, locale["event.end-time"]),
				new NumberEdit!float(0.1, "end-time", 16, 0.0, maxTime, 0.1, end),
				new Label(0.1, 16, locale["event.camera.easing"]),
				new TextEdit(0.1, "easing", 16, easing),
				new ScriptableWidget!Nothing(0, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
					// update event properties
					// TODO: make this undoable
					auto nstart = win.get!(NumberEdit!float)("start-time").value;
					auto nend = win.get!(NumberEdit!float)("end-time").value;
					if(nstart != start || nend != end) {
						start = nstart;
						end = nend;
						state.sortChannel(channel);
					}
					easing = win.get!TextEdit("easing").text;
				})
			));
			state.openWindow(win);
		}
	}

	///
	void grabbed(State state, Vector!int mouse) {
		grabbedPost = post.region.contains(mouse);
		grabbedZoom = post.zoomRegion.join(ante.zoomRegion).contains(mouse);
		grabbedPos = grabbedPost ? mouse-post.center : mouse-ante.center;
	}

	///
	void grabMove(State state, Vector!int mouse) {
		if(grabbedZoom) {
			ViewState* vs = grabbedPost ? &post : &ante;
			auto m = state.currentView.invTransform(mouse.to!float);
			// TODO: this currently only cares about the x coordinate (meaning dragging
			// only works as expected on that axis) make this work on all axes.
			vs.zoom = snap(abs(state.cameraView.screenSize.x/(2*(m.x-vs.translation.x))), 2f);
		} else {
			Vector!(float)* vec = grabbedPost ? &post.translation : &ante.translation;
			*vec = state.currentView.invTransform((mouse-grabbedPos).to!float).snap(state.snap);
		}
	}

	///
	Variant getGrabInfo() => Variant(Tuple!(ViewState, ViewState)(ante, post));

	///
	void setGrabInfo(Variant var) {
		auto tuple = var.get!(Tuple!(ViewState, ViewState));
		ante = tuple[0];
		post = tuple[1];
	}
	
	///
	Cloneable clone(State state) => new CameraEvent(start, end, easing, ante.translation, ante.zoom, post.translation, post.zoom);

}

/// Event that shows an image
class ImageEvent : Event, Placeable, SceneGrabbable, Cloneable {
	/// Global image scale, multiplied by [scale], to get the final scale.
	enum GLOBAL_SCALE = 1/40f;

	Image image = null; /// Image to display
	string path; /// Image path
	Vector!float pos; /// Position
	float scale; /// Image scale

	private Vector!int grabbedPos;
	private Rect!int lastRect;

	///
	this(float start, float end, Vector!float pos, float scale, string path) {
		super(start, end);
		this.pos = pos;
		this.scale = scale;
		this.path = path;
	}
	
	/// Renders the image
	void render(State state) {
		auto img = image is null ? state.missingImage : image;
		auto sceneRect = Rect!float(pos, Vector!float(img.width, img.height)*scale*GLOBAL_SCALE);
		auto rect = state.currentView.transform(sceneRect);
		lastRect = rect.to!int;
		if(!state.currentView.visible.collides(sceneRect))
			return; // cull
		auto sdlRect = rect.toSDL();
		SDL_RenderCopyF(state.window.rend, img.texture, null, &sdlRect);
	}

	///
	override void time(State state, float rel, float abs) {
		render(state);
	}
	
	///
	void preview(State state) {
		render(state);
	}

	///
	void placeMove(State state, Vector!int mouse) {
		pos = state.currentView.invTransform(mouse.to!float).snap(state.snap);
	}

	///
	void place(State state) {
		state.addEvent(this);
	}

	///
	void remove(State state) {
		state.removeEvent(this);
	}

	///
	Variant getGrabInfo() => Variant(pos);

	///
	void setGrabInfo(Variant var) {
		pos = var.get!(Vector!float);
	}

	///
	void grabbed(State state, Vector!int mouse) {
		grabbedPos = mouse-lastRect.pos;
	}

	///
	void grabMove(State state, Vector!int mouse) {
		pos = state.currentView.invTransform((mouse-grabbedPos).to!float).snap(state.snap);
	}
	
	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(state.playTime < start || state.playTime > end)
			return ClickResponse.PASS;
		if(lastRect.contains(mouse)) {
			if(button == MouseButton.MIDDLE)
				return ClickResponse.GRAB;
			if(button == MouseButton.RIGHT)
				return ClickResponse.CLICK;
			return ClickResponse.BLOCK;
		}
		return ClickResponse.PASS;
	}

	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		if(button == MouseButton.RIGHT) {
			// open object window
			Window win;
			float maxTime = state.audio is null ? float.infinity : state.audio.duration;
			win = new Window(locale["event.image.title"], Rect!int(0, 0, 300, 300), true, new VBox(1,
				new Label(0.1, 16, locale["event.start-time"]),
				new NumberEdit!float(0.1, "start-time", 16, 0.0, maxTime, 0.1, start),
				new Label(0.1, 16, locale["event.end-time"]),
				new NumberEdit!float(0.1, "end-time", 16, 0.0, float.infinity, 0.1, end),
				new Label(0.1, 16, locale["event.image.scale"]),
				new NumberEdit!float(0.1, "scale", 16, 0.1, 16, 0.1, scale),
				new Label(0.1, 16, locale["event.image.image-path"]),
				new TextEdit(0.1, "path", 16, path),
				new Button(0.1, 16, locale["event.image.load-image"], { loadImage(state); }),
				new ScriptableWidget!Nothing(0, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
					// update event properties
					// TODO: make this undoable
					start = win.get!(NumberEdit!float)("start-time").value;
					end = win.get!(NumberEdit!float)("end-time").value;
					scale = win.get!(NumberEdit!float)("scale").value;
					path = win.get!TextEdit("path").text;
				})
			));
			state.openWindow(win);
		}
	}

	///
	void loadImage(State state) {
		if(path == "")
			return;
		image = Image.load(state.window, buildPath(projDir(state.name), path));
	}
	
	///
	override void postInit(State state) {
		loadImage(state);
	}

	///
	Cloneable clone(State state) {
		auto evt = new ImageEvent(start, end, pos, scale, path);
		evt.postInit(state);
		return evt;
	}
}

/// Event that shows a box made of text.
class BoxEvent : Event, Placeable, SceneGrabbable, Cloneable {
	enum CORNER = "+"; /// Corner character
	enum HORIZ = "-"; /// Horizontal character
	enum VERT = "|"; /// Vertical character
	
	Vector!float pos; /// Position of this box
	Vector!int size; /// Size of this box
	float fontSize; /// Size of the font
	Color bg; /// Background color
	Color fg; /// Foreground color
	
	/**
		Region of the box when rendered onto the screen. The rects in this region are
		ordered like so:

		* rects[0] = top (excluding last plus)
		* rect[1] = left (excluding last plus)
		* rects[2] = right
		* rects[3] = bottom
	*/
	Region!int region;

	private Vector!int grabbedPos;
	private bool grabbedRight, grabbedBottom;
	
	///
	this(float start, float end, Vector!float pos, Vector!int size, float fontSize, Color fg, Color bg) {
		super(start, end);
		this.pos = pos;
		this.size = size;
		this.fontSize = fontSize;
		this.fg = fg;
		this.bg = bg;
	}
	
	/// Renders the box
	void render(State state, ubyte alpha) {
		string rep(string s, size_t n) {
			auto ap = appender!string;
			ap.reserve(n*s.length);
			for(size_t i = 0; i < n; i++)
				ap ~= s;
			return ap[];
		}
		auto horiz = rep(HORIZ, size.x-2);
		auto vert = rep(VERT~'\n', size.y-2);
		auto fgc = fg.withAlpha(alpha);
		auto bgc = bg.withAlpha(alpha);
		region.rects = [
			// top
			state.font.render(state.window.rend, fgc, bgc, state.currentView, pos, fontSize, CORNER~horiz).to!int,
			// left
			state.font.render(state.window.rend, fgc, bgc, state.currentView, pos+Vector!float(0, 1)*fontSize, fontSize, vert).to!int,
			// right
			// the extra ~" " below is to make the bottom and right boxes overlap, so
			// when grabbing the bottom right corner, you scale both sides.
			state.font.render(state.window.rend, fgc, bgc, state.currentView, pos+Vector!float(size.x-1, 0)*fontSize, fontSize, CORNER~"\n"~vert~" ").to!int,
			// bottom
			state.font.render(state.window.rend, fgc, bgc, state.currentView, pos+Vector!float(0, size.y-1)*fontSize, fontSize, CORNER~horiz~CORNER).to!int,
		];
	}

	///
	override void time(State state, float rel, float abs) {
		render(state, 255);
	}
	
	///
	void preview(State state) {
		render(state, 128);
	}

	///
	void placeMove(State state, Vector!int mouse) {
		pos = state.currentView.invTransform(mouse.to!float).snap(state.snap);
	}

	///
	void place(State state) {
		state.addEvent(this);
	}

	///
	void remove(State state) {
		state.removeEvent(this);
	}

	///
	Variant getGrabInfo() => Variant(Tuple!(Vector!float, Vector!int)(pos, size));

	///
	void setGrabInfo(Variant var) {
		auto tup = var.get!(Tuple!(Vector!float, Vector!int));
		pos = tup[0];
		size = tup[1];
	}

	///
	void grabbed(State state, Vector!int mouse) {
		grabbedRight = region.rects[2].contains(mouse);
		grabbedBottom = region.rects[3].contains(mouse);
		grabbedPos = mouse-region.rects[0].pos;
	}

	///
	void grabMove(State state, Vector!int mouse) {
		if(!grabbedRight && !grabbedBottom) {
			pos = state.currentView.invTransform((mouse-grabbedPos).to!float).snap(state.snap);
			return;
		}
		auto off = ((state.currentView.invTransform(mouse.to!float)-pos)/fontSize).to!int;
		if(off.x < 3)
			off.x = 3;
		if(off.y < 3)
			off.y = 3;
		if(grabbedRight)
			size.x = off.x;
		if(grabbedBottom)
			size.y = off.y;
	}
	
	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(state.playTime < start || state.playTime > end)
			return ClickResponse.PASS;
		if(region.contains(mouse)) {
			if(button == MouseButton.MIDDLE)
				return ClickResponse.GRAB;
			if(button == MouseButton.RIGHT)
				return ClickResponse.CLICK;
			return ClickResponse.BLOCK;
		}
		return ClickResponse.PASS;
	}

	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		if(button == MouseButton.RIGHT) {
			// open object window
			Window win;
			float maxTime = state.audio is null ? float.infinity : state.audio.duration;
			win = new Window(locale["event.box.title"], Rect!int(0, 0, 300, 300), true, new VBox(1,
				new Label(0.1, 16, locale["event.start-time"]),
				new NumberEdit!float(0.1, "start-time", 16, 0.0, maxTime, 0.1, start),
				new Label(0.1, 16, locale["event.end-time"]),
				new NumberEdit!float(0.1, "end-time", 16, 0.0, float.infinity, 0.1, end),
				new Label(0.1, 16, locale["event.font-size"]),
				new NumberEdit!float(0.1, "font-size", 16, 1.0, float.infinity, 0.1, fontSize),
				new Label(0.1, 16, locale["event.foreground"]),
				new ColorSelector(0.1, "foreground", 16, fg),
				new Label(0.1, 16, locale["event.background"]),
				new ColorSelector(0.1, "background", 16, bg),
				new ScriptableWidget!Nothing(0, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
					// update text properties
					// TODO: make this undoable
					start = win.get!(NumberEdit!float)("start-time").value;
					end = win.get!(NumberEdit!float)("end-time").value;
					fontSize = win.get!(NumberEdit!float)("font-size").value;
					fg = win.get!ColorSelector("foreground").color;
					bg = win.get!ColorSelector("background").color;
				})
			));
			state.openWindow(win);
		}
	}

	///
	Cloneable clone(State state) => new BoxEvent(start, end, pos, size, fontSize, fg, bg);
}
