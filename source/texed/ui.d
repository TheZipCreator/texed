/// Contains user interface components
module texed.ui;

import std.datetime.stopwatch, std.conv, std.utf;
import core.time : Duration;

import texed.types, texed.sdl, texed.state, texed.misc, texed.locale;

/// What to do upon a click
enum ClickResponse {
	GRAB, /// Should be returned when the object should be grabbed
	SELECT, /// Should be returned when the object should be selected
	CLICK, /// Should be returned when the object is clicked. If it's a grabbable, this should be in an area where it can't be grabbed (e.g. non-object parts of a window)
	BLOCK, /// Should be returned when the object isn't clicked, but does block other clicks.
	PASS /// Should be returned when the object should not be grabbed.
}

/// Mouse button used
enum MouseButton {
	LEFT, /// left button
	MIDDLE, /// middle button
	RIGHT, /// right button
	OTHER /// another, more mysterious, button
}

/// Converts SDL button index to a mouse button
MouseButton buttonFromIndex(int idx) {
	switch(idx) {
		case 1:
			return MouseButton.LEFT;
		case 2:
			return MouseButton.MIDDLE;
		case 3:
			return MouseButton.RIGHT;
		default:
			return MouseButton.OTHER;
	}
}

/// Events to listen to
enum Listen {
	CHARACTER, /// [CharacterEvent]
	KEY, /// [KeyEvent]
}

/// An input event
abstract class InputEvent {}

/// Event fired when a character is sent
class CharacterEvent : InputEvent {
	dchar which; /// Character that was pressed
	
	///
	this(dchar which) {
		this.which = which;
	}
}

/// Event fired when a key is sent
class KeyEvent : InputEvent {
	SDL_Keysym keysym; /// The keysym

	///
	this(SDL_Keysym keysym) {
		this.keysym = keysym;
	}
}

/// Anything that is clickable
interface Clickable {
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse); /// Called whenever a mouse click occurs.
	void clicked(State state, MouseButton button, Vector!int mouse); /// Called when the object is clicked
}

/// Anything that is grabbable
interface Grabbable : Clickable {
	void grabbed(State state, Vector!int mouse); /// Called when the object is grabbed. `mouse` is the current mouse position
	void grabMove(State state, Vector!int mouse); /// Called when the object is moved. `mouse` is the current mouse position
}

/// Anything that is selected after clicking (such as a text field)
interface Selectable : Clickable {
	int listens(); /// Bitflag of what this object listens to. See [Listen] for options.
	void input(State state, InputEvent evt); /// Receives an input event.
}

/// A theme color
enum ThemeColor {
	PRIMARY, /// Primary accent color
	SECONDARY, /// Secondary accent color
	BACKGROUND, /// Background color
	FOREGROUND, /// For things on the background color
	ERROR, /// Error color
	TRANSPARENT /// Always transparent; not configurable
}

/// A theme
struct Theme {
	///
	Color primary, secondary, background, foreground, error;

	/// Gets the color for the corresponding enum
	Color of(ThemeColor col) {
		final switch(col) {
			case ThemeColor.PRIMARY: return primary;
			case ThemeColor.SECONDARY: return secondary;
			case ThemeColor.BACKGROUND: return background;
			case ThemeColor.FOREGROUND: return foreground;
			case ThemeColor.ERROR: return error;
			case ThemeColor.TRANSPARENT: return Color.TRANSPARENT;
		}
	}
	
	/// Default dark theme
	enum DARK = Theme(
		Color(128, 0, 255, 255),
		Color(128, 255, 0, 255),
		Color(0, 0, 0, 255),
		Color(255, 255, 255, 255),
		Color(255, 0, 0, 255)
	);
}

/// A window
class Window : Grabbable {
	string title; /// Title of the window
	Rect!int rect; /// Rect of the window.
	Widget widget; /// The primary widget. Use a container if you want more than one.
	bool closable; /// Whether the window can be closed
	bool minimized = false; /// Whether the window is minimized or not
	bool closeClicked = false; /// Signals if this window should be closed

	Vector!int grabbedPos; /// Where the window was grabbed

	enum int TITLE_SIZE = 16; /// Size of a title bar in pixels.
	enum int TITLE_FONT_SIZE = TITLE_SIZE-2; /// Title font size
	
	///
	this(string title, Rect!int rect, bool closable, Widget widget) {
		this.title = title;
		this.rect = rect;
		this.widget = widget;
		this.closable = closable;
	}
	
	///
	Rect!int titleCharRect(int charIndex) {
		return Rect!int(rect.pos+Vector!int(rect.size.x-charIndex*TITLE_FONT_SIZE+1, 1-TITLE_SIZE), Vector!int(TITLE_FONT_SIZE, TITLE_FONT_SIZE));
	}
	
	/// Renders the window
	void render(State state) {
		auto rend = state.window.rend;
		if(!minimized) {
			// draw window
			SDL_Rect r = rect.toSDL();
			state.theme.background.withAlpha(128).draw(rend);
			SDL_RenderFillRect(rend, &r);
			state.theme.foreground.draw(rend);
			SDL_RenderDrawRect(rend, &r);
		}
		{
			// draw title
			SDL_Rect r = titleRect.toSDL();
			state.theme.background.withAlpha(128).draw(rend);
			SDL_RenderFillRect(rend, &r);
			state.theme.foreground.draw(rend);
			SDL_RenderDrawRect(rend, &r);
			state.font.render(rend, state.theme.foreground, Color.TRANSPARENT, null, rect.pos.to!float+Vector!float(1, 1-TITLE_SIZE), TITLE_FONT_SIZE, clip(title, (rect.size.x-2)/TITLE_FONT_SIZE-2));
			auto mrect = titleCharRect(2).to!float, xrect = titleCharRect(1).to!float;
			state.font.render(rend, state.theme.foreground, Color.TRANSPARENT, null, mrect.pos, TITLE_FONT_SIZE, minimized ? 'v' : '^');
			if(closable)
				state.font.render(rend, state.theme.error, Color.TRANSPARENT, null, xrect.pos, TITLE_FONT_SIZE, 'X');

		}
		// draw widget
		if(!minimized)
			widget.render(state, rect);
	}

	/// Gets the title rectangle
	@property Rect!int titleRect() => Rect!int(rect.pos-Vector!int(0, TITLE_SIZE), Vector!int(rect.size.x, TITLE_SIZE));
	
	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(button == MouseButton.LEFT && titleRect.contains(mouse))
			return ClickResponse.GRAB;
		if((!minimized && rect.contains(mouse)) || titleRect.contains(mouse))
			return ClickResponse.CLICK;
		return ClickResponse.PASS;
	}
	
	///
	void grabbed(State state, Vector!int mouse) {
		grabbedPos = mouse-rect.pos;
	}
	
	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		if(titleRect.contains(mouse)) {
			if(titleCharRect(2).contains(mouse))
				minimized = !minimized;
			else if(titleCharRect(1).contains(mouse) && closable)
				closeClicked = true;
			return;
		}
	}

	///
	void grabMove(State state, Vector!int mouse) {
		rect.pos = mouse-grabbedPos;
		clampInPlace(&rect.pos.x, 0, cast(int)state.editorView.screenSize.x-rect.size.x);
		if(minimized)
			clampInPlace(&rect.pos.y, TITLE_SIZE, cast(int)state.editorView.screenSize.y);
		else
			clampInPlace(&rect.pos.y, TITLE_SIZE, cast(int)state.editorView.screenSize.y-rect.size.y);
	}

	/// Gets all clickable elements within. (These need to be pushed to clickables **before** the window)
	Clickable[] collectClickables() {
		Clickable[] ret;
		widget.collectClickables(ret);
		return ret;
	}

	// this shouldn't be necessary, but for some reason if I try to do:
	// T get(T : Widget)(string id, Widget root = widget)
	// and just have it be one method, I get:
	// Error: need `this` to access member `widget`
	// which is an error that normally happens when you try to call an instance method like
	// a static method, but that obviously isn't happening here. so I don't know what the
	// compiler wants from me but this is a workaround that works so whatever.
	private T getImpl(T : Widget)(string id, Widget root) {
		if(root.id == id) {
			if(auto ret = cast(T)root)
				return ret;
		}
		foreach(c; root.getChildren) {
			auto w = getImpl!T(id, c);
			if(w !is null)
				return w;
		}
		return null;
	}

	/// Gets the widget with the given ID. Returns null if it can't be found
	T get(T : Widget)(string id) => getImpl!T(id, widget);
}

/// A widget
abstract class Widget {
	string id; /// ID of the widget. Set to the empty string if not utilized
	float size; /// How much space this widget should be given in the container it's in, from 0 to 1. 
	
	///
	this(float size, string id = "") {
		this.size = size;
		this.id = id;
	}
	
	/// Renders the widget
	void render(State state, Rect!int rect) {}

	/// Collects clickable children
	void collectClickables(ref Clickable[] ret) {}
	
	/// Gets all children of the widget
	Widget[] getChildren() => [];
}

/// Margin for another widget
class Margin : Widget {
	Widget inner; /// The inner widget
	int px; /// Pixel amount of the margin.

	///
	this(float size, int px) {
		super(size);
		this.px = px;
	}

	///
	override void render(State state, Rect!int rect) {
		inner.render(state, Rect!int(rect.pos+px, rect.size-2*px));
	}

	///
	override void collectClickables(ref Clickable[] ret) {
		inner.collectClickables(ret);
	}

	///
	override Widget[] getChildren() => [inner];
}

/// Template for both HBox and VBox
private class Box(Vector!float offset) : Widget {
	enum complement = Vector!float(offset.y, offset.x);

	Widget[] children; /// Children in the box
	int margin = 2; /// Margin

	///
	this(T...)(float size, T t) {
		super(size);
		static foreach(widget; t) {
			static assert(is(typeof(widget) : Widget), "All children must be widgets.");
			children ~= widget;
		}
	}

	///
	override void render(State state, Rect!int rect) {
		float dist = 0;
		auto rs = rect.size.to!float;
		foreach(c; children) {
			c.render(state, Rect!int(
				rect.pos+(rs*offset*dist).to!int + Vector!int(margin, margin),
				(rs*(complement+offset*c.size)).to!int - Vector!int(2*margin, 2*margin)
			));
			dist += c.size;
		}
	}

	///
	override void collectClickables(ref Clickable[] ret) {
		foreach(c; children)
			c.collectClickables(ret);
	}

	///
	override Widget[] getChildren() => children;
}

/// Vertical box
alias VBox = Box!(Vector!float(0, 1));
/// Horizontal box
alias HBox = Box!(Vector!float(1, 0));

/// A label
class Label : Widget {
	string text; /// Text in the label
	float fontSize; /// Size of the font
	ThemeColor color = ThemeColor.FOREGROUND; /// Color
	
	///
	this(float size, float fontSize, string text) {
		super(size);
		this.fontSize = fontSize;
		this.text = text;
	}
	
	///
	this(float size, float fontSize, ThemeColor color, string text) {
		super(size);
		this.fontSize = fontSize;
		this.text = text;
		this.color = color;
	}

	///
	override void render(State state, Rect!int rect) {
		string clipped = clip(text, cast(int)(rect.size.x/fontSize));
		auto centered = rect.pos.to!float+rect.size.to!float/2-Vector!float(fontSize*clipped.length/2, fontSize/2);
		state.font.render(state.window.rend, state.theme.of(color), Color.TRANSPARENT, null, centered, fontSize, clipped);
	}
}

/// A button
class Button : Widget, Clickable {
	string text; /// Text in the button
	float fontSize; /// Size of the font in the button
	ThemeColor textColor = ThemeColor.FOREGROUND; /// Text color
	ThemeColor backgroundColor = ThemeColor.FOREGROUND; /// Background color
	ThemeColor activatedColor = ThemeColor.PRIMARY; /// Color when pressed

	void delegate() action; /// Action to perform when pressed

	StopWatch clickedTime; /// Time since last pressed

	Rect!int lastRect; /// Last rectangle this button was rendered at

	enum float ANIMATION_DUR = 250; /// Length of animation when clicked
	
	///
	this(float size, float fontSize, string text, typeof(action) action) {
		super(size);
		this.fontSize = fontSize;
		this.text = text;
		this.action = action;
		clickedTime.setTimeElapsed(msecs(cast(long)ANIMATION_DUR));
		clickedTime.start();
	}
	
	///
	this(float size, float fontSize, ThemeColor textColor, ThemeColor backgroundColor, ThemeColor activatedColor, string text, typeof(action) action) {
		this(size, fontSize, text, action);
		this.textColor = textColor;
		this.backgroundColor = backgroundColor;
		this.activatedColor = activatedColor;
	}
	
	///
	override void render(State state, Rect!int rect) {
		lastRect = rect;
		// draw border
		auto sdlRect = rect.toSDL();
		Color.interp(state.theme.of(activatedColor), state.theme.of(backgroundColor), clamp(clickedTime.peek.total!"msecs"/ANIMATION_DUR, 0.0, 1.0)).draw(state.window.rend);
		SDL_RenderDrawRect(state.window.rend, &sdlRect);
		// draw text. TODO: refactor so this doesn't repeat code from `Label`
		string clipped = clip(text, cast(int)(rect.size.x/fontSize));
		auto centered = rect.pos.to!float+rect.size.to!float/2-Vector!float(fontSize*clipped.length/2, fontSize/2);
		state.font.render(state.window.rend, state.theme.of(textColor), Color.TRANSPARENT, null, centered, fontSize, clipped);
	}
	
	///
	override void collectClickables(ref Clickable[] ret) {
		ret ~= this;
	}
	
	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(lastRect.contains(mouse))
			return button == MouseButton.LEFT ? ClickResponse.CLICK : ClickResponse.BLOCK;
		return ClickResponse.PASS;
	}

	///
	void clicked(State state, MouseButton button, Vector!int mouse) {
		clickedTime.reset();
		action();
	}
}

/// An editable text line
class TextEdit : Widget, Selectable {
	
	mixin TextEditor!(false);

	ThemeColor activeColor; /// Color when selected
	ThemeColor borderColor; /// Color of the border
	ThemeColor textColor; /// Color of the text
	string placeholder; /// Placeholder text
	float fontSize; /// Font size
	bool clipText; /// Whether text should be clipped

	private Rect!int lastRect;

	///
	this(float size, string id, float fontSize, string text = "", string placeholder = "", ThemeColor borderColor = ThemeColor.FOREGROUND, ThemeColor textColor = ThemeColor.FOREGROUND, ThemeColor activeColor = ThemeColor.PRIMARY, bool clipText = true) {
		super(size, id);
		this.text = text;
		this.placeholder = placeholder == "" ? locale["ui.placeholder"] : placeholder;
		this.cursorPos = text.length;
		this.fontSize = fontSize;
		this.borderColor = borderColor;
		this.textColor = textColor;
		this.activeColor = activeColor;
		this.clipText = clipText;
	}

	///
	override void render(State state, Rect!int rect) {
		lastRect = rect;

		bool usePlaceholder = text == "";
		bool isSelected = state.selected == this;
		
		auto rend = state.window.rend;
		auto sdlRect = rect.toSDL();
		state.theme.of(isSelected ? activeColor : borderColor).draw(rend);
		SDL_RenderDrawRect(rend, &sdlRect);
		string clipped = usePlaceholder ? placeholder : text;
		if(clipText)
			clipped = clip(clipped, cast(int)(rect.size.x/fontSize));
		auto centered = rect.pos.to!float+Vector!float(0, rect.size.y/2-fontSize/2);
		state.font.render(state.window.rend, state.theme.of(textColor).withAlpha(usePlaceholder ? 128 : 255), Color.TRANSPARENT, null, centered, fontSize, clipped, isSelected ? cursorPos : size_t.max);
	}

	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(lastRect.contains(mouse))
			return button == MouseButton.LEFT ? ClickResponse.SELECT : ClickResponse.BLOCK;
		return ClickResponse.PASS;
	}

	///
	void clicked(State state, MouseButton button, Vector!int mouse) {}

	///
	int listens() => Listen.CHARACTER | Listen.KEY;

	///
	void input(State state, InputEvent evt) {
		editText(state, evt);
	}
	
	///
	override void collectClickables(ref Clickable[] ret) {
		ret ~= this;
	}
}

/// A widget for spacing
class Spacing : Widget {
	///
	this(float size) {
		super(size, "");
	}
}

/// A horizontal bar
class HBar : Widget {
	ThemeColor color; /// Color of the bar
	int margin; /// Margin of the bar

	///
	this(float size, int margin = 5, ThemeColor color = ThemeColor.FOREGROUND) {
		super(size, "");
		this.color = color;
		this.margin = margin;
	}

	///
	override void render(State state, Rect!int rect) {
		state.theme.of(color).draw(state.window.rend);
		SDL_RenderDrawLine(state.window.rend, rect.pos.x+margin, rect.pos.y+rect.size.y/2, rect.pos.x+rect.size.x-margin, rect.pos.y+rect.size.y/2);
	}
}

/// Like a TextEdit but only for numbers.
class NumberEdit(Number) : Widget, Grabbable {
	static assert(is(Number : int) || is(Number : float));
	
	Number value; /// Current value
	Number min; /// Minimum
	Number max; /// Maximum
	Number step; /// Step
	private TextEdit text;

	/// `step` may be set to zero if not wanted
	this(float size, string id, float fontSize, Number min, Number max, Number step, Number num, string placeholder = "", ThemeColor borderColor = ThemeColor.FOREGROUND, ThemeColor textColor = ThemeColor.FOREGROUND, ThemeColor activeColor = ThemeColor.PRIMARY) {
		super(size, id);
		this.min = min;
		this.max = max;
		this.step = step;
		this.value = num;
		text = new TextEdit(size, id, fontSize, num.to!string, placeholder, borderColor, textColor, activeColor, false);
		text.text = value.to!string;
	}
	
	///
	override void render(State state, Rect!int rect) {
		// change value
		if(state.selected != text && text.text != value.to!string) {
			try {
				value = text.text.to!Number;
			} catch(ConvException) {}
			clampInPlace(&value, min, max);
			text.text = value.to!string;
			clampInPlace(&text.cursorPos, 0, text.text.length);
		}
		// render slider thing
		static if(is(Number : float)) {
			if(min == -float.infinity || min == float.infinity || max == -float.infinity || max == float.infinity) {
				// slider can't be rendered (or used)
				text.render(state, rect);
				return;
			}
		}
		float progress = (value-min)/cast(float)(max-min);
		auto sdlRect = rect.toSDL();
		sdlRect.w = cast(int)(sdlRect.w*progress);
		state.theme.of(text.activeColor).withAlpha(128).draw(state.window.rend);
		SDL_RenderFillRect(state.window.rend, &sdlRect);
		// render TextEdit
		text.render(state, rect);
	}
	
	///
	override void collectClickables(ref Clickable[] ret) {
		ret ~= this;
		ret ~= text;
	}

	///
	ClickResponse mouseClick(State state, MouseButton button, Vector!int mouse) {
		if(text.lastRect.contains(mouse) && button == MouseButton.MIDDLE)
			return ClickResponse.GRAB;
		return ClickResponse.PASS;
	}
	
	///
	void clicked(State state, MouseButton button, Vector!int mouse) {}

	///
	void grabbed(State state, Vector!int mouse) {}

	///
	void grabMove(State state, Vector!int mouse) {
		float progress = (mouse.x-text.lastRect.pos.x)/cast(float)(text.lastRect.size.x);
		value = lerp!Number(min, max, progress);
		if(step != 0)
			value = cast(Number)((cast(long)(value/step))*step);
		clampInPlace(&value, min, max);
		text.text = value.to!string;
		clampInPlace(&text.cursorPos, 0, text.text.length);

	}

}

/// A widget that can do any action upon being rendered.
class ScriptableWidget(Data) : Widget {
	alias Script = void delegate(ScriptableWidget!Data self, State state, Rect!int rect);
	/// Stored data
	Data data;
	/// Script to execute
	Script script;

	///
	this(float size, string id, Data data, Script script) {
		super(size, id);
		this.data = data;
		this.script = script;
	}

	///
	override void render(State state, Rect!int rect) {
		script(this, state, rect);
	}
}

/// A color selector
class ColorSelector : Widget {
	private {
		HBox hbox;
		NumberEdit!int r, g, b, a;
	}

	this(float size, string id, float fontSize, Color col) {
		super(size, id);
		r = new NumberEdit!int(1/5f, "", fontSize, 0, 255, 16, col.r);
		g = new NumberEdit!int(1/5f, "", fontSize, 0, 255, 16, col.g);
		b = new NumberEdit!int(1/5f, "", fontSize, 0, 255, 16, col.b);
		a = new NumberEdit!int(1/5f, "", fontSize, 0, 255, 16, col.a);
		hbox = new HBox(1,
			new ScriptableWidget!Nothing(1/5f, "", Nothing(), delegate(ScriptableWidget!Nothing self, State state, Rect!int rect) {
				auto sdlRect = rect.toSDL();
				color.draw(state.window.rend);
				SDL_RenderFillRect(state.window.rend, &sdlRect);
				state.theme.foreground.draw(state.window.rend);
				SDL_RenderDrawRect(state.window.rend, &sdlRect);
			}),
			r, g, b, a
		);
	}

	///
	override void render(State state, Rect!int rect) {
		hbox.render(state, rect);
	}

	///
	override void collectClickables(ref Clickable[] ret) {
		ret ~= r;
		ret ~= g;
		ret ~= b;
		ret ~= a;
	}
	
	/// Gets the current color
	@property Color color() {
		return Color(r.value.to!ubyte, g.value.to!ubyte, b.value.to!ubyte, a.value.to!ubyte);
	}

}
