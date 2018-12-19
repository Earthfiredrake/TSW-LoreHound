// Copyright 2015, eltorqiro
// Released under the terms of the MIT License
// https://github.com/eltorqiro/TSW-Utils
// Modified for EFD SWL Mod Framework:
//   Copyright 2017-2018, Earthfiredrake
//   Used and released under the terms of the MIT License
//   https://github.com/Earthfiredrake/SWL-FrameworkMod

/**
 *
 * Provides a common interface for managing Gui Edit Mode (gem) handling for movieclips
 *
 * Target clips that are to be managed by this controller should contain a SignalGeometryChanged, which is emitted whenever a change in size, scale, or position of the clip occurs.
 * If this is not implemented, then the gem overlay for the clip will not know when the clip is moved by things other than the overlay being dragged.  This may not be important for some clips which don't move any other time.
 *
 * - only create instance of the controller using the create() factory method, do not instantiate using new GemController()
 *
 */

import flash.geom.Point;

import gfx.core.UIComponent;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "GemController.lcl.as"
	/**
	 * do not call this directly
	 */
	public function GemController() {

		dragging = false;
		clickEvent = null;
		dragOverlay = null;

		prevMousePos = null;

		overlays = [ ];

		if ( groupMoveModifiers == undefined ) {

			groupMoveModifiers = [
				{	button: 1,
					keys: [
						Key.SHIFT
					]
				}
			];
		}

		if ( overlayLinkage == undefined ) {
			overlayLinkage = "GemOverlay";
		}

		if ( overlayPadding == undefined ) {
			overlayPadding = 5;
		}

	}

	private function draw() : Void {

		// remove previous overlays
		var overlay:GemOverlay;
		while ( overlay = GemOverlay( overlays.pop() ) ) {
			overlay.removeMovieClip();
		}

		// add new overlays
		for ( var i:Number = 0; i < _targets.length; i++ ) {

			if ( !targets[i] ) continue;

			var overlay:GemOverlay = GemOverlay( MovieClipHelper.attachMovieWithClass( overlayLinkage, GemOverlay, "", this, getNextHighestDepth(), { target: _targets[i], padding: overlayPadding } ) );

			overlay.addEventListener( "press", this, "pressHandler" );
			overlay.addEventListener( "release", this, "releaseHandler" );

			overlay.addEventListener( "scrollWheel", this, "scrollWheelHandler" );

			overlays.push( overlay );

		}

	}

	private function pressHandler( event:Object ) : Void {

		prevMousePos = new Point( _xmouse, _ymouse );

		dragOverlay = event.target;
		clickEvent = event;

		// right click moves all groups
		moveOverlays = event.button == 1 ? overlays : [ dragOverlay ];

		onMouseMove = function() {

			var diff:Point = new Point( _xmouse - prevMousePos.x, _ymouse - prevMousePos.y );
			if (lockedAxis & 1) { diff.x = 0; }
			if (lockedAxis & 2) { diff.y = 0; }

			if ( !dragging ) {
				dragging = true;
				dispatchEvent( { type: "startDrag", overlay: dragOverlay } );

				for ( var s:String in moveOverlays ) {
					dispatchEvent( { type: "targetStartDrag", overlay: moveOverlays[s] } );
				}

			}

			dispatchEvent( { type: "drag", overlay: dragOverlay, delta: diff } );

			for ( var s:String in moveOverlays ) {
				moveOverlays[s].moveBy( diff );
				dispatchEvent( { type: "targetDrag", overlay: moveOverlays[s], delta: diff } );
			}

			prevMousePos = new Point( _xmouse, _ymouse );

		}

	}

	// Lock an axis to prevent movement along it
	// 0 : None (unlock)
	// 1 : x
	// 2 : y
	// 3 : x+y (prevent movement)
	public function lockAxis(axisID:Number) {
		lockedAxis = axisID;
	}

	private function releaseHandler( event:Object ) : Void {

		if ( dragging ) {
			dispatchEvent( { type: "endDrag", overlay: dragOverlay } );

			for ( var s:String in moveOverlays ) {
				dispatchEvent( { type: "targetEndDrag", overlay: moveOverlays[s] } );
			}

			moveOverlays = undefined;
			dragging = false;
		}

		else {
			dispatchEvent( { type: "click", overlay: clickEvent.target, button: clickEvent.button, shift: clickEvent.shift, ctrl: clickEvent.ctrl } );
		}

		clickEvent = null;
		dragOverlay = null;
		onMouseMove = undefined;
	}

	private function scrollWheelHandler( event:Object ) : Void {
		dispatchEvent( { type: "scrollWheel", overlay: event.target, delta: event.delta } );
	}

	/**
	 * factory method for creating a new instance of GemController
	 *
	 * @param	name
	 * @param	parent
	 * @param	depth
	 *
	 * @return
	 */
	public static function create( name:String, parent:MovieClip, depth:Number, targets ) : GemController {

		return GemController( MovieClipHelper.createMovieWithClass( GemController, name, parent, depth, { targets: targets } ) );

	}

	/**
	 * internal variables
	 */

	private var dragging:Boolean;
	private var clickEvent:Object;
	private var dragOverlay:GemOverlay;

	private var moveOverlays:Array;

	private var prevMousePos:Point;
	private var lockedAxis:Number = 0;

	private var overlays:Array;

	private var groupMoveModifiers:Array;

	private var overlayLinkage:String;
	private var overlayPadding:Number;

	/**
	 * properties
	 */

	private var _targets:Array;
	public function get targets() { return _targets; }
	public function set targets( value ) {

		if ( value instanceof MovieClip ) {
			_targets = [ value ];
		}

		else {
			_targets = value;
		}

		initialized && invalidate();
	}

}
