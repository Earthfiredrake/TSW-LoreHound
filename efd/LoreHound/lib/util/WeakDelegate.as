// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-LoreHound

import com.Utils.WeakPtr;

class efd.LoreHound.lib.util.WeakDelegate {
	public static function Create(obj:Object, func:Function):Function {
		var f = function() {
			var target:WeakPtr = arguments.callee.target;
			var _func:Function = arguments.callee.func;
			return _func.apply(target.Get(), arguments);
		};
		f.target = new WeakPtr(obj);
		f.func = func;
		return f;
	}
}
