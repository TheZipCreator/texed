/// Contains logic for actions (things you can do/undo)
module texed.action;

import std.variant;

import texed.state, texed.types, texed.event;

/// The action interface
interface Action {
	void perform(State state); /// Does the action
	void undo(State state); /// Undoes the action
}

/// Places a [Placeable]
class PlaceAction : Action {
	Placeable placeable; /// The placeable
	
	///
	this(Placeable placeable) {
		this.placeable = placeable;
	}
	
	///
	void perform(State state) {
		placeable.place(state);
	}

	///
	void undo(State state) {
		placeable.remove(state);
	}
}

/// Removes a [Placeable]
class RemoveAction : Action {
	Placeable placeable; /// The placeable
	
	///
	this(Placeable placeable) {
		this.placeable = placeable;
	}
	
	///
	void perform(State state) {
		placeable.remove(state);
	}

	///
	void undo(State state) {
		placeable.place(state);
	}
}

/// Grabs a [SceneGrabbable]
class GrabAction : Action {
	SceneGrabbable sg; /// The SceneGrabbable
	Variant anteInfo; /// Info before doing the grab
	Variant postInfo; /// Info after doing the grab
	
	///
	this(SceneGrabbable sg, Variant anteInfo, Variant postInfo) {
		this.sg = sg;
		this.anteInfo = anteInfo;
		this.postInfo = postInfo;
	}
	
	///
	void perform(State state) {
		sg.setGrabInfo(postInfo);
	}

	///
	void undo(State state) {
		sg.setGrabInfo(anteInfo);
	}
}
