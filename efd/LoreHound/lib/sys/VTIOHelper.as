// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// LinkVTIO subsystem implementation
// Dependencies: None (Icon and Config optional)
// InitObj:
//   ConfigDV:String (default undefined) Name of DistributedValue to attach to the VTIO mod's configuration UI
// Handles registration with VTIO compatible topbar and container mods
// Generally included if a mod has an icon, but can be used for any mod

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.Utils.WeakPtr;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "VTIOHelper.lcl.as"
	public static function Create(mod:Mod, initObj:Object):VTIOHelper {
		return new VTIOHelper(mod, initObj);
	}

	private function VTIOHelper(mod:Mod, initObj:Object) {
		ModPtr = new WeakPtr(mod);
		ConfigDV = initObj.ConfigDV;
		ViperDV = DistributedValue.Create("VTIO_IsLoaded");
		mod.SignalLoadCompleted.Connect(LoadCompleted, this);
		mod.Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "TopbarIntegration") {
			if (ViperDV.GetValue()) {
				if (newValue) { LinkWithTopbar(); }
				else {
					DetachTopbarListeners();
					// NOTE: A /reloadui is strongly recommended after "detaching" from a VTIO topbar
					//       As VTIO does not provide a method of de-registering, the mod tries to fake it (to varied success)
					Mod.ChatMsg(LocaleManager.GetString("General", "RemoveVTIO"));
				}
			}
		}
	}

	private function LoadCompleted():Void {
		if (!ModPtr.Get().Config) { LinkWithTopbar(); return; } // Config not in use, auto link
		// DEPRECATED(v1.0.0): Temporary upgrade support (use of 'undefined')
		var integration:Boolean = ModPtr.Get().Config.GetValue("TopbarIntegration", false);
		if (integration == undefined || integration) { LinkWithTopbar(); }
	}

/// Topbar registration
	// Most container mods support the legacy VTIO interface
	private function LinkWithTopbar():Void {
		// Try to register now, in case they loaded first, otherwise signup to detect if they load
		DoTopbarRegistration(ViperDV);
		ViperDV.SignalChanged.Connect(DoTopbarRegistration, this);
	}

	private function DoTopbarRegistration(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			var mod:Mod = ModPtr.Get();
			mod.Config.SetValue("TopbarIntegration", true); // DEPRECATED(v1.0.0) Temporary upgrade support

			// TODO: Completing icon extraction
			// Adjust icon to be better suited for topbar integration
			mod.Icon.VTIOMode = true;

			// Doing this more than once messes with Meeehr's, will have to find alternate workaround for ModFolder
			if (!RegisteredWithTopbar) {
				// Note: Viper's *requires* all five values, regardless of whether the icon exists or not
				//       Both are capable of handling "undefined" or otherwise invalid icon names
				var topbarInfo:Array = [mod.ModName, Mod.DevName, mod.Version, ConfigDV, mod.Icon.toString()];
				DistributedValue.SetDValue("VTIO_RegisterAddon", topbarInfo.join('|'));
			}
			// VTIO creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, Meeehr's redirects event handling oddly
			// (It calls back to the original clip, using the new clip as the "this" instance)
			// And just to be different, ModFolder doesn't create a copy at all, it just uses the one we give it
			// In which case we don't want to lose our current reference
			if (mod.HostClip.Icon != undefined) {
				mod.Icon.CopyToTopbar(mod.HostClip.Icon);
				mod.Icon._visible = false; // Usually the topbar will do this for us, but it's not so good about it during a re-register
				mod.Icon = mod.HostClip.Icon;
				mod.Icon.Refresh();
			}
			RegisteredWithTopbar = true;
			// WORKAROUND: ModFolder has a nasty habit of leaving the VTIO_IsLoaded flag set during reloads
			// Would be very nice to get in contact with Icarus on this
			// Seem to have found a way to do this that doesn't cause problems with Meeehr's, still requires an explicit check above though :(
			if (!DistributedValue.GetDValue("ModFolder")) {
				// Other topbar mods don't need to be reregistered (Meeehr's has issues with it)
				// Deferred to prevent mangling ongoing signal handling
				setTimeout(Delegate.create(this, DetachTopbarListeners), 1, dv);
			}
		} else {
			// WORKAROUND: ModFolder part deux
			RegisteredWithTopbar = false;
		}
	}

	// This needs to be deferred so that the disconnection doesn't muddle the ongoing processing
	private function DetachTopbarListeners():Void {	ViperDV.SignalChanged.Disconnect(DoTopbarRegistration, this); }

	private var ModPtr:WeakPtr;
	private var ViperDV:DistributedValue;
	private var ConfigDV:String;
	private var RegisteredWithTopbar:Boolean = false;
}
