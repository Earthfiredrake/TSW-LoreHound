// Copyright 2015, eltorqiro
// Released under the terms of the MIT License
// https://github.com/eltorqiro/TSW-Utils
// Modified for LoreHound:
//   Copyright 2017, Earthfiredrake (Peloprata)
//   Used and released under the terms of the MIT License
//   https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.core.UIComponent;
import com.Utils.Rect;
import flash.geom.Point;


/**
 * Used by the GemController to create individual overlays around each gem target
 *
 * This cannot be instantiated using new GemOverlay(), but must instead be attached to a movieclip symbol.  However, creating instances of GemOverlay outside of GemController is reasonably useless.
 *
 */
class efd.LoreHound.lib.etu.GemOverlay extends UIComponent {

	public static var __className:String = "efd.LoreHound.lib.etu.GemOverlay";

	public function GemOverlay() {

		if ( _padding == undefined ) {
			_padding = 5;
		}

	}

	private function configUI() : Void {

		target.SignalGeometryChanged.Connect( invalidate, this );

		// add right click handling
		this["onPressAux"] = onPress;
		this["onReleaseAux"] = onReleaseOutside = this["onReleaseOutsideAux"] = onRelease;

	}

	private function draw() : Void {

		var bounds:Object = target.getBounds( this._parent );

		var topLeft:Point = new Point( bounds.xMin, bounds.yMin );
		this._parent.localToGlobal( topLeft );
		topLeft.x -= padding;
		topLeft.y -= padding;
		this._parent.globalToLocal( topLeft );

		_x = topLeft.x;
		_y = topLeft.y;

		var size:Point = new Point( Math.abs( bounds.xMin - bounds.xMax ), Math.abs( bounds.yMin - bounds.yMax ) );
		this._parent.localToGlobal( size );
		size.x += padding * 2;
		size.y += padding * 2;
		this._parent.globalToLocal( size );

		_width = size.x;
		_height = size.y;

	}

	public function moveBy( relative:Point ) : Void {

		var topLeft:Point = new Point( _x + relative.x, _y + relative.y );

		_x = topLeft.x;
		_y = topLeft.y;

		topLeft.x += padding;
		topLeft.y += padding;
		target._parent.globalToLocal( topLeft );

		// offset by bounds amount to cater for targets whose content is not aligned to 0,0
		var bounds:Object = target.getBounds();
		topLeft.x -= bounds.xMin * target._xscale / 100;
		topLeft.y -= bounds.yMin * target._yscale / 100;

		target._x = topLeft.x;
		target._y = topLeft.y;

	}

	private function onRollOver() : Void {
		gotoAndStop( "lit" );
	}

	private function onRollOut() : Void {
		gotoAndStop( "unlit" );
	}

	private function onPress( controllerIdx:Number, keyboardOrMouse:Number, button:Number ) : Void {
		dispatchEvent( { type: "press", shift: Key.isDown(Key.SHIFT), ctrl: Key.isDown(Key.CONTROL), button:button } );
	}

	private function onRelease() : Void {

		if ( !hitTest(_root._xmouse, _root._ymouse, true) ) {
			gotoAndStop( "unlit" );
		}

		dispatchEvent( { type: "release" } );

	}

	private function scrollWheel( delta:Number ) : Void {
		dispatchEvent( { type: "scrollWheel", delta: delta } );
	}

	/**
	 * internal variables
	 */

	/**
	 * properties
	 */

	public var target:MovieClip;

	private var _padding:Number;
	public function get padding() : Number { return _padding; }
	public function set padding( value:Number ) : Void {
		_padding = value;
		invalidate();
	}
}
